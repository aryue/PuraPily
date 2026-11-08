/* libyuv is not vendored in this tree; -1 makes the overlay fall back to swscale. */
#include "ijksdl_image_convert.h"

int ijk_image_convert(int width, int height,
    enum AVPixelFormat dst_format, uint8_t **dst_data, int *dst_linesize,
    enum AVPixelFormat src_format, const uint8_t **src_data, const int *src_linesize)
{
    (void)width; (void)height; (void)dst_format; (void)dst_data; (void)dst_linesize;
    (void)src_format; (void)src_data; (void)src_linesize;
    return -1;
}
