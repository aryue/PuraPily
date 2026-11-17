"""Rebuild the HarmonyOS layered app icon from the flat master artwork.

Input : AppScope/resources/base/media/app_icon_v5.png (1024x1024 flat icon)
Output: foreground.png + background.png in BOTH
        AppScope/resources/base/media and entry/src/main/resources/base/media

Both layers are 1024x1024 PNG, square, full-bleed, with no baked-in rounded
corners and no artificial padding:
  * foreground = white play-button "P" on 100% transparent surrounding area
  * background = opaque smooth blue/orange gradient, no transparent pixels

Both module directories receive identical bytes because AppScope resources
overwrite same-named module resources at packaging time.

Usage:
  python scripts/build-layered-icon.py                 # gradient background
  python scripts/build-layered-icon.py --solid        # solid brand-blue background
  python scripts/build-layered-icon.py --preview      # also write a preview sheet

Requires: numpy, opencv-python-headless, Pillow
  python -m pip install numpy opencv-python-headless Pillow
"""
import argparse
import os
import cv2
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASTER = os.path.join(ROOT, 'AppScope', 'resources', 'base', 'media', 'app_icon_v5.png')
TARGETS = [
    os.path.join(ROOT, 'AppScope', 'resources', 'base', 'media'),
    os.path.join(ROOT, 'entry', 'src', 'main', 'resources', 'base', 'media'),
]
PREVIEW_DIR = os.path.join(ROOT, '.local', 'icon-work')


def split(master, solid=False):
    bgr = cv2.imread(master, cv2.IMREAD_COLOR)
    if bgr is None:
        raise SystemExit('cannot read ' + master)
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    f = rgb.astype(np.float32)
    mn, mx = f.min(2), f.max(2)
    sat = (mx - mn) / (mx + 1.0)
    h, w = mn.shape
    assert (w, h) == (1024, 1024), 'master icon must be 1024x1024'

    # 1) GrabCut: near-neutral bright core = definite foreground; saturated
    #    gradient far from the glass = definite background. Reflections ON the
    #    glass must stay eligible, otherwise the silhouette gets notches.
    core = ((sat < 0.16) & (mn > 205)).astype(np.uint8)
    core = cv2.erode(core, np.ones((5, 5), np.uint8), iterations=2)
    near_core = cv2.dilate(core, np.ones((101, 101), np.uint8)) > 0
    yy, xx = np.mgrid[0:h, 0:w]
    outside = (xx < 150) | (xx > 910) | (yy < 80) | (yy > 950)
    seed = np.full((h, w), cv2.GC_PR_BGD, np.uint8)
    seed[((sat > 0.55) | (mn < 105)) & ~near_core] = cv2.GC_BGD
    seed[outside] = cv2.GC_BGD
    seed[core > 0] = cv2.GC_FGD
    possible = (sat < 0.45) & (mn > 118)
    seed[possible & (seed == cv2.GC_PR_BGD)] = cv2.GC_PR_FGD
    bgd = np.zeros((1, 65), np.float64)
    fgd = np.zeros((1, 65), np.float64)
    cv2.grabCut(bgr, seed, None, bgd, fgd, 6, cv2.GC_INIT_WITH_MASK)
    hard = np.isin(seed, [cv2.GC_FGD, cv2.GC_PR_FGD]).astype(np.uint8)
    _, labels, stats, _ = cv2.connectedComponentsWithStats(hard, 8)
    hard = (labels == (1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA])))).astype(np.uint8)

    # 2) Keep the play-triangle opening, drop specks, smooth the silhouette.
    cnts, hier = cv2.findContours(hard, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
    big_holes = np.zeros_like(hard)
    small_holes = np.zeros_like(hard)
    if hier is not None:
        for i, c in enumerate(cnts):
            if hier[0][i][3] < 0:
                continue
            cv2.drawContours(big_holes if cv2.contourArea(c) > 6000 else small_holes,
                             [c], -1, 1, -1)
    hard[small_holes > 0] = 1
    hard[big_holes > 0] = 0
    hard = cv2.morphologyEx(hard, cv2.MORPH_CLOSE, np.ones((21, 21), np.uint8))
    hard = cv2.morphologyEx(hard, cv2.MORPH_OPEN, np.ones((7, 7), np.uint8))
    hard[big_holes > 0] = 0
    hard = cv2.medianBlur(hard, 7)
    hard = (cv2.GaussianBlur(hard.astype(np.float32), (0, 0), 2.5) > 0.5).astype(np.uint8)
    hard[big_holes > 0] = 0

    # 3) Solid core + 1px anti-aliased rim, everywhere else exactly alpha=0.
    inner = cv2.erode(hard, np.ones((3, 3), np.uint8))
    alpha = cv2.GaussianBlur(hard.astype(np.float32) * 255, (0, 0), 0.7)
    alpha[hard == 0] = 0
    alpha[inner == 1] = 255
    alpha = np.clip(alpha, 0, 255)
    a = alpha / 255.0
    fg = np.dstack([np.where(a[..., None] > 0.002, f, 0).astype(np.uint8),
                    alpha.astype(np.uint8)])

    # 4) Background: full-bleed, fully opaque. Normalized convolution from
    #    non-foreground pixels yields a clean gradient with no leftover
    #    silhouette, shadow or transparent padding.
    if solid:
        brand = np.median(f[720:980, 20:280].reshape(-1, 3), axis=0)
        bg = np.empty((h, w, 3), np.uint8)
        bg[:] = brand.astype(np.uint8)
    else:
        valid = (hard == 0).astype(np.float32)
        num = cv2.GaussianBlur(f * valid[..., None], (0, 0), 110)
        den = cv2.GaussianBlur(valid, (0, 0), 110)
        bg = np.clip(num / np.maximum(den[..., None], 1e-4), 0, 255).astype(np.uint8)

    return rgb, bg, fg, a


def preview(rgb, bg, fg, a, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    comp = (rgb.astype(np.float32) * a[..., None] +
            bg.astype(np.float32) * (1 - a[..., None])).astype(np.uint8)
    grey = np.empty_like(rgb); grey[:] = (110, 110, 110)
    fg_rgb = fg[..., :3]
    fg_on_grey = (fg_rgb * a[..., None] + grey * (1 - a[..., None])).astype(np.uint8)

    def tile(im):
        return np.array(Image.fromarray(im).convert('RGB').resize((400, 400)))

    row1 = np.hstack([tile(rgb), tile(np.dstack([fg[..., 3]] * 3)), tile(fg_on_grey)])
    row2 = np.hstack([tile(bg), tile(comp), tile(rgb)])
    Image.fromarray(np.vstack([row1, row2])).save(os.path.join(out_dir, 'layered-icon-preview.png'))
    Image.fromarray(comp).save(os.path.join(out_dir, 'layered-icon-composite.png'))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--solid', action='store_true',
                    help='use a solid brand-blue background instead of a gradient')
    ap.add_argument('--preview', action='store_true', help='write a preview sheet')
    args = ap.parse_args()

    rgb, bg, fg, a = split(MASTER, solid=args.solid)
    for d in TARGETS:
        Image.fromarray(bg).save(os.path.join(d, 'background.png'))
        Image.fromarray(fg).save(os.path.join(d, 'foreground.png'))
        print('wrote', d)
    if args.preview:
        preview(rgb, bg, fg, a, PREVIEW_DIR)
        print('preview ->', PREVIEW_DIR)
    print('foreground: %.1f%% opaque, %.1f%% transparent' %
          ((a == 1).mean() * 100, (a == 0).mean() * 100))
    print('background mode:', 'solid' if args.solid else 'gradient')


if __name__ == '__main__':
    main()
