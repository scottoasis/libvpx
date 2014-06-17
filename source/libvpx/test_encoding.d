module libvpx.test;

import libvpx.libvpx;
import std.stdio;

struct ivf_file_header {
	align(1):
		char d = 'D';
		char k = 'K';
		char i = 'I';
		char f = 'F';
		short ver = 0;
		short headersize = 32;
		int fourcc = 0x30385056;
		short width;
		short height;
		int timebase_den;
		int timebase_num;
		int framecount;
		int unused = 0;
}

void write_ivf_file_header(vpx_codec_enc_cfg_t config, uint framecount, File stream) {
	auto header = ivf_file_header();
	header.width = cast(short)config.g_w;
	header.height = cast(short)config.g_h;
	header.timebase_den = config.g_timebase.den;
	header.timebase_num = config.g_timebase.num;
	header.framecount = framecount;
	auto packed = (cast(ubyte *)(&header))[0..32];
	stream.rawWrite(packed);
}

struct ivf_frame_header {
	align(1):
	int framesize;
	int pts_lo;
	int pts_ho;
}

void write_ivf_frame_header(vpx_codec_cx_pkt_t pkt, File stream) {
	auto header = ivf_frame_header(cast(int)pkt.data.frame.sz, cast(int)(pkt.data.frame.pts & 0xffffffff), cast(int)((pkt.data.frame.pts >> 32) & 0xffffffff));
	auto packed = (cast(ubyte *)(&header))[0..12];
	stream.rawWrite(packed);
}

unittest {
	auto video = File("/Users/scott/Desktop/test.webm", "w");
	video.seek(32, SEEK_SET); // skip file header area first

	auto audition = File("/Users/scott/Desktop/test.yuv");
	ubyte[] buffer;
	audition.seek(0, SEEK_END);
	auto length = audition.tell();
	buffer.length = length;
	audition.seek(0, SEEK_SET);
	audition.rawRead(buffer);
	auto image_width = 720;
	auto image_height = 871;

	vpx_codec_cx_pkt_t * pkt;

	vpx_codec_enc_cfg_t config;
	vpx_codec_ctx_t     codec;
	auto res = vpx_codec_enc_config_default(vpx_codec_vp8_cx(), &config, 0);

	config.g_w = image_width;
	config.g_h = image_height;
	vpx_rational_t timebase = {1, 100};
	config.g_timebase = timebase;
	res = vpx_codec_enc_init(&codec, vpx_codec_vp8_cx(), &config, 0);

	uint framecount = 0;
	while (framecount < 200) {
		vpx_image_t image;
		vpx_img_alloc(&image, vpx_img_fmt.VPX_IMG_FMT_YV12, image_width, image_height, 1);
		auto chrominance_plane_size = (image_width / 2 * image_height / 2);
		auto luminance_plane_size = 4 * chrominance_plane_size;
		image.planes[0] = buffer.ptr;
		image.planes[1] = buffer.ptr + luminance_plane_size;
		image.planes[2] = buffer.ptr + luminance_plane_size + chrominance_plane_size;

		res = vpx_codec_encode(&codec, &image, framecount, 1, 0x0, VPX_DL_REALTIME);
		vpx_codec_iter_t iter = null;
		pkt = vpx_codec_get_cx_data(&codec, &iter);
		while (pkt) {
			if ((* pkt).kind == vpx_codec_cx_pkt_kind.VPX_CODEC_CX_FRAME_PKT) {
				auto size = (* pkt).data.frame.sz;
				ubyte[] buf = cast(ubyte[])(* pkt).data.frame.buf[0..size];
				write_ivf_frame_header((* pkt), video);
				video.rawWrite(buf);
			}
			pkt = vpx_codec_get_cx_data(&codec, &iter);
		}

		vpx_img_free(&image);
		framecount += 1;
	}

	video.seek(0, SEEK_SET);
	write_ivf_file_header(config, framecount, video);
}