"""Check actual emulator screenshots from native back-to-top press/drag/release."""
import json
from pathlib import Path

import numpy as np
from PIL import Image

root = Path(__file__).resolve().parents[1] / 'artifacts/other-card-edge-light-20261029'
cases = [
    ('backtop-landscape-drag', (700, 1000, 32, 37), (700, 1000, 300, 1200), (700, 1000, 1490, 1495)),
    ('backtop-landscape-right', (650, 950, 2523, 2528), (650, 950, 1700, 2300), (650, 950, 1461, 1466)),
]


def region(image, rect):
    y1, y2, x1, x2 = rect
    return image[y1:y2, x1:x2]


metrics = {}
for name, edge, center, distant_edge in cases:
    before, held, released = [np.array(Image.open(root / f'{name}-{stage}.jpeg')).astype(float)
                              for stage in ['before', 'held', 'released']]
    delta = held - before
    rgb = region(delta, edge).mean((0, 1))
    center_delta = np.abs(region(delta, center)).mean()
    distant_delta = np.abs(region(delta, distant_edge)).mean()
    release_delta = np.abs(region(released - before, edge)).mean()
    assert rgb[0] > 5 and rgb[0] > max(rgb[1], rgb[2]) + 5, (name, 'actual red incident light', rgb)
    assert center_delta < .1, (name, 'center must not receive light', center_delta)
    assert distant_delta < .1, (name, 'light must follow source location', distant_delta)
    assert release_delta < .1, (name, 'release must extinguish rim light', release_delta)
    metrics[name] = {'edge_rgb': rgb.tolist(), 'center': float(center_delta),
                     'distant_edge': float(distant_delta), 'released_edge': float(release_delta)}

(root / 'backtop-red-metrics.json').write_text(json.dumps(metrics, indent=2), encoding='utf8')
print('PASS: actual back-to-top red light follows left/right position, affects rims only and clears after native drag release.')
