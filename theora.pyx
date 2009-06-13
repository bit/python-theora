cdef extern from "stdlib.h":
    ctypedef unsigned long size_t
    void *malloc (size_t size)
    void free(void *mem)
    void *memcpy(void *dst, void *src, long n)

cdef extern from "arrayobject.h":

    ctypedef int intp

    ctypedef extern class numpy.ndarray [object PyArrayObject]:
        cdef char *data
        cdef int nd
        cdef intp *dimensions
        cdef intp *strides
        cdef int flags

cdef extern from "theora/theoradec.h":

    ctypedef unsigned int ogg_uint32_t
    ctypedef long long ogg_int64_t

    ctypedef struct ogg_sync_state:
        pass
    ctypedef struct th_comment:
        pass
    ctypedef struct th_info:
        ogg_uint32_t  frame_width
        ogg_uint32_t  frame_height
        ogg_uint32_t  pic_width
        ogg_uint32_t  pic_height
        ogg_uint32_t  pic_x
        ogg_uint32_t  pic_y
        ogg_uint32_t  fps_numerator
        ogg_uint32_t  fps_denominator
        ogg_uint32_t  aspect_numerator
        ogg_uint32_t  aspect_denominator
    ctypedef struct ogg_stream_state:
        long serialno
    ctypedef struct ogg_page:
        pass
    ctypedef struct ogg_packet:
        pass
    ctypedef struct th_setup_info:
        pass
    ctypedef struct th_dec_ctx:
        pass
    ctypedef struct th_ycbcr_buffer:
        pass
    ctypedef struct th_img_plane:
        int width
        int height
        int stride
        unsigned char *data
    ctypedef th_img_plane th_ycbcr_buffer[3]

    int ogg_sync_init(ogg_sync_state *oy)
    void th_comment_init(th_comment *_tc)
    void th_info_init(th_info *_info)
    char *ogg_sync_buffer(ogg_sync_state *oy, long size)
    int ogg_sync_wrote(ogg_sync_state *oy, long bytes)
    int ogg_sync_pageout(ogg_sync_state *oy, ogg_page *og)
    int ogg_page_bos(ogg_page *og)
    int ogg_stream_pagein(ogg_stream_state *os, ogg_page *og)
    int ogg_page_serialno(ogg_page *og)
    int ogg_stream_init(ogg_stream_state *os, int serialno)
    int ogg_stream_packetout(ogg_stream_state *os, ogg_packet *op)
    int th_decode_headerin(th_info *_info,th_comment *_tc,
             th_setup_info **_setup,ogg_packet *_op)
    int ogg_stream_clear(ogg_stream_state *os)
    th_dec_ctx *th_decode_alloc(th_info *_info, th_setup_info *_setup)
    double th_granule_time(void *_encdec, ogg_int64_t _granpos)
    int th_decode_packetin(th_dec_ctx *_dec, ogg_packet *_op,
             ogg_int64_t *_granpos)
    void th_decode_free(th_dec_ctx *_dec)
    int ogg_sync_clear(ogg_sync_state *oy)
    void th_info_clear(th_info *_info)
    void th_comment_clear(th_comment *_tc)
    int th_decode_ycbcr_out(th_dec_ctx *_dec, th_ycbcr_buffer _ycbcr)

cimport numpy as np

cdef class Theora:
    cdef object _infile
    cdef ogg_sync_state _oy
    cdef th_comment _tc
    cdef th_info _ti
    cdef ogg_page _og
    cdef ogg_stream_state _to
    cdef ogg_packet _op
    cdef th_setup_info *_setup
    cdef th_dec_ctx *_td
    cdef int _frame
    cdef double _time

    def __init__(self, f):
        self._infile = f
        ogg_sync_init(&self._oy)
        th_comment_init(&self._tc)
        th_info_init(&self._ti)
        self._setup = NULL
        self._frame = 0
        self._time = 0.
        self.read_headers()

    def __del__(self):
        th_comment_clear(&self._tc)
        th_info_clear(&self._ti)
        ogg_sync_clear(&self._oy)
        ogg_stream_clear(&self._to)
        th_decode_free(self._td)


    @property
    def frame(self):
        return self._frame

    @property
    def time(self):
        return self._time

    cdef int buffer_data(self, int n=4096):
        """
        Reads "n" bytes from self._infile into the ogg_sync_state "oy".
        """
        s = self._infile.read(n)
        cdef int bytes=len(s)
        cdef char *buffer=ogg_sync_buffer(&self._oy, n)
        cdef char *m=s
        memcpy(buffer, m, n)
        ogg_sync_wrote(&self._oy, bytes)
        return bytes

    def YCbCr_tuple2array(self, YCbCr):
        """
        Converts the YCbCr tuple to one numpy (w, h, 3) array.

        It also automatically rescales Cb and Cr if necessary (Theora encoder
        sometimes reduces their width/height twice compared to Y).
        """
        from numpy import concatenate, zeros_like
        Y, Cb, Cr = YCbCr
        Cb2 = zeros_like(Y)
        for i in range(Cb2.shape[0]):
            for j in range(Cb2.shape[1]):
                Cb2[i, j] = Cb[i/2, j/2]
        Cr2 = zeros_like(Y)
        for i in range(Cr2.shape[0]):
            for j in range(Cr2.shape[1]):
                Cr2[i, j] = Cr[i/2, j/2]
        w, h = Y.shape
        Y = Y.reshape((w, h, 1))
        Cb = Cb2.reshape((w, h, 1))
        Cr = Cr2.reshape((w, h, 1))
        A = concatenate((Y, Cb, Cr), axis=2)
        return A

    def YCbCr2RGB(self, np.ndarray[np.uint8_t, ndim=3] A):
        """
        Converts the the (w, h, 3) array from YCbCr into RGB.
        """
        cdef int w, h, i, j
        cdef int Y, Cb, Cr
        cdef unsigned char R, G, B
        w = A.shape[0]
        h = A.shape[1]
        cdef np.ndarray[np.uint8_t, ndim=3] A_out = A.copy()
        for i in range(w):
            for j in range(h):
                Y = A[i, j, 0]
                Cb = A[i, j, 1]
                Cr = A[i, j, 2]
                YCbCr2RGB_fast_c(Y, Cb, Cr, &R, &G, &B)
                A_out[i, j, 0] = <int>R
                A_out[i, j, 1] = <int>G
                A_out[i, j, 2] = <int>B
        return A_out

    def get_frame_data(self):
        """
        Reads the image data and returns a tuple (Y, Cb, Cr).

        This is the lowest level API. Note that Cb and Cr may have twice lower
        dimension than Y (the higher level API take care of that).
        """
        from numpy import zeros
        cdef th_ycbcr_buffer ycbcr
        if th_decode_ycbcr_out(self._td, ycbcr) != 0:
            raise Exception("th_decode_ycbcr_out failed\n")
        cdef int n
        cdef ndarray Y
        cdef char *Yp
        r = []
        for i in range(3):
            n = ycbcr[i].stride*ycbcr[i].height
            Y = zeros(n, dtype = "uint8")
            Yp = <char *>Y.data
            memcpy(Yp, ycbcr[i].data, n)
            Y = Y.reshape((ycbcr[i].height, ycbcr[i].stride))
            Y = Y[:, :ycbcr[i].width]
            r.append(Y)
        return r

    def get_frame_image(self):
        from scipy.misc import toimage
        A = self.YCbCr_tuple2array(self.get_frame_data())
        return toimage(self.YCbCr2RGB(A), channel_axis=2)

    def read_headers(self):
        """
        Reads headers of the theora file.
        """
        cdef ogg_stream_state test
        stateflag = True
        theora_p = False
        while stateflag:
            ret = self.buffer_data();
            if ret == 0:
                raise Exception("End of file while searching for headers 1")
            while ogg_sync_pageout(&self._oy, &self._og) > 0:
                if ogg_page_bos(&self._og) == 0:
                    if theora_p:
                        ogg_stream_pagein(&self._to, &self._og)
                    stateflag = False
                    break
                ogg_stream_init(&test, ogg_page_serialno(&self._og))
                ogg_stream_pagein(&test, &self._og)
                ogg_stream_packetout(&test, &self._op)
                # is this the first theora stream?
                if not theora_p and \
                        th_decode_headerin(&self._ti, &self._tc,
                            &self._setup, &self._op) >= 0:
                    # yes, read it to self._to
                    memcpy(&self._to, &test, sizeof(test))
                    theora_p = True
                else:
                    # no, skip it
                    ogg_stream_clear(&test)
        while theora_p > 0 and (theora_p < 3):
            ret = ogg_stream_packetout(&self._to, &self._op)
            while theora_p > 0 and (theora_p < 3) and ret != 0:
                if ret < 0:
                    raise Exception("Error parsing headers 1")
                if th_decode_headerin(&self._ti, &self._tc,
                        &self._setup, &self._op) < 0:
                    raise Exception("Error parsing headers 2")
                theora_p += 1
                if theora_p == 3: break
                ret = ogg_stream_packetout(&self._to, &self._op)
            if ogg_sync_pageout(&self._oy, &self._og) > 0:
                if theora_p > 0: ogg_stream_pagein(&self._to, &self._og)
            else:
                ret = self.buffer_data()
                if ret == 0:
                    raise Exception("End of file while searching for headers 2")
        if self._ti.fps_denominator == 0:
            raise Exception("fps_denominator is zero")
        print "Ogg logical stream %lx is Theora %dx%d %.02f fps video\n" \
            "Encoded frame content is %dx%d with %dx%d offset\n" \
            "Aspect: %d:%d\n" % (
            self._to.serialno, self._ti.pic_width, self._ti.pic_height,
            float(self._ti.fps_numerator)/self._ti.fps_denominator,
            self._ti.frame_width, self._ti.frame_height,
            self._ti.pic_x, self._ti.pic_y,
            self._ti.aspect_numerator, self._ti.aspect_denominator)

        self._td = th_decode_alloc(&self._ti, self._setup)
        if self._td == NULL:
            raise Exception("th_decode_alloc failed: the decoding parameters are invalid")

    def read_frame(self):
        """
        Reads the next frame and returns.
        """
        cdef ogg_int64_t videobuf_granulepos = -1
        while 1:
            # do we have enough data to form a packet?
            if ogg_stream_packetout(&self._to, &self._op) > 0:
                # yes, decode it using theora and return
                th_decode_packetin(self._td, &self._op,
                        &videobuf_granulepos)
                self._time = th_granule_time(self._td, videobuf_granulepos)
                self._frame += 1
                return True
            else:
                # no, we need to read more data
                if self.buffer_data() == 0:
                    # EOF reached
                    return False
                while ogg_sync_pageout(&self._oy, &self._og) > 0:
                    ogg_stream_pagein(&self._to, &self._og)

cdef inline unsigned char clip(int a):
    if a > 255:
        return 255
    elif a < 0:
        return 0
    else:
        return a

cdef void YCbCr2RGB_fast_c(unsigned char Y, unsigned char Cb, unsigned char
        Cr, unsigned char *R, unsigned char *G, unsigned char* B):
    """
    Converts from YCbCr to RGB using a very fast C integer arithmetics.

    Assumes both YCbCr and RGB are between 0..255

    This is a C version of the function. If you are in Python, use
    YCbCr2RGB_fast.
    """
    cdef int C, D, E
    C = Y - 16
    D = Cb - 128
    E = Cr - 128

    R[0] = clip((298*C + 409*E + 128) >> 8)
    G[0] = clip((298*C - 100*D - 208*E + 128) >> 8)
    B[0] = clip((298*C + 516*D + 128) >> 8)

def YCbCr2RGB_fast(YCbCr):
    """
    Converts from YCbCr to RGB using a very fast C integer arithmetics.

    Assumes both YCbCr and RGB are between 0..255
    """
    from numpy import array
    cdef unsigned char R, G, B
    Y, Cb, Cr = YCbCr
    YCbCr2RGB_fast_c(Y, Cb, Cr, &R, &G, &B)
    return array([R, G, B], dtype="uint8")
