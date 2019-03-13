//
//  ViewController.m
//  VideoEncoder
//
//  Created by donglingxiao on 2019/3/12.
//  Copyright © 2019 donglingxiao. All rights reserved.
//

#import "ViewController.h"
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    [self setUpView];
}

- (void)setUpView {
    self.view.backgroundColor = [UIColor whiteColor];
    UIButton *clickButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [clickButton setFrame:CGRectMake(0, 0, 100, 80)];
    clickButton.center = self.view.center;
    clickButton.backgroundColor = [UIColor redColor];
    [clickButton setTitle:@"decode" forState:UIControlStateNormal];
    [clickButton addTarget:self action:@selector(buttonClicked) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:clickButton];
}

- (void)buttonClicked {
    AVFormatContext *pFormatCtx;
    AVOutputFormat *fmt;
    AVStream *video_st;
    AVCodecContext *pCodecCtx;
    AVCodec *pCodec;
    AVPacket pkt;
    uint8_t *picture_buf;
    AVFrame *pFrame;
    int picture_size;
    int y_size;
    int frameCnt =0;
    
    
    int in_w = 480, in_h = 272;
    int frameNum = 100;
    char input_str_full[500]={0};
    char output_str_full[500]={0};
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    NSString *input_nsstr= [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"ds.yuv"];
    sprintf(input_str_full,"%s",[input_nsstr UTF8String]);
    FILE *in_file = fopen(input_str_full, "rb");
    
    NSString *output_nsstr= [documentsDirectory stringByAppendingPathComponent:@"ds.mp4"];
    sprintf(output_str_full,"%s",[output_nsstr UTF8String]);
    av_register_all();
    pFormatCtx = avformat_alloc_context();
    //guess format
    fmt = av_guess_format(NULL, output_str_full, NULL);
    pFormatCtx->oformat = fmt;

    int openResult =avio_open(&pFormatCtx->pb, output_str_full, AVIO_FLAG_WRITE);
    if (openResult <0) {
        
        NSLog(@"Failed to open output file!%d path--%@",openResult,output_nsstr);
        return;
    }
    video_st = avformat_new_stream(pFormatCtx,0);

    if(video_st == NULL){
        return ;
    }

    //Param that must be set
    pCodecCtx = video_st->codec;
    pCodecCtx->codec_id = fmt->video_codec;
    pCodecCtx->codec_type = AVMEDIA_TYPE_VIDEO;
    pCodecCtx->pix_fmt = AV_PIX_FMT_YUV420P;
    pCodecCtx->width = in_w;
    pCodecCtx->height = in_h;
    pCodecCtx->bit_rate = 400000;
    pCodecCtx->gop_size = 250;
    
    pCodecCtx->time_base.num = 1;
    pCodecCtx->time_base.den = 25;
    
    pCodecCtx->qmin = 10;
    pCodecCtx->qmax = 51;
    
    pCodecCtx->max_b_frames =3;
    
    AVDictionary *param = 0;
    
    //H.264
    if (pCodecCtx->codec_id == AV_CODEC_ID_H264) {
        av_dict_set(&param, "preset", "slow", 0);
        av_dict_set(&param, "tune", "zerolatency", 0);
    }
    
    //show some information
    av_dump_format(pFormatCtx, 0, output_str_full, 1);
    
    pCodec = avcodec_find_encoder(pCodecCtx->codec_id);
    if (!pCodec) {
        printf("can not find encoder! \n");
        return ;
    }
    
    if (avcodec_open2(pCodecCtx, pCodec, &param) <0) {
        printf("Failed to open encoder! \n");
        return ;
    }
    
    pFrame = av_frame_alloc();
    picture_size = avpicture_get_size(pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height);
    picture_buf = (uint8_t *)av_malloc(picture_size);
    avpicture_fill((AVPicture *)pFrame, picture_buf, pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height);
    
    //wite file header
    avformat_write_header(pFormatCtx, NULL);
    av_new_packet(&pkt, picture_size);
    
    y_size = pCodecCtx->width * pCodecCtx->height;
    
    for (int i=0; i<frameNum; i++) {
        if (fread(picture_buf, 1, y_size*3/2, in_file ) <= 0) {
            printf("Failed to read raw data! \n");
            return ;
        }else if (feof(in_file)){
            break ;
        }
        
        pFrame->data[0] = picture_buf;                   // Y
        pFrame->data[1] = picture_buf + y_size;          // U
        pFrame->data[2] = picture_buf + y_size*5/4 ;     // V
        
        
        //PTS
        pFrame->pts = i*(video_st->time_base.den)/((video_st->time_base.num)*25);
        int got_picture = 0;
        //Encode
        int ret = avcodec_encode_video2(pCodecCtx, &pkt, pFrame, &got_picture);
        if (ret <0) {
            printf("Failed to encode! \n");
            return ;
        }
        if (got_picture == 1) {
            printf("Succeed to encode frame : %5d\tsize:%5d\n   index :%5d\n",frameCnt,pkt.size,video_st->index);
            frameCnt++;
            pkt.stream_index = video_st->index;
            ret = av_write_frame(pFormatCtx, &pkt);
            av_free_packet(&pkt);
        }
   
    }
    
    int ret = flush_encoder(pFormatCtx, 0);
    if (ret <0) {
        printf("Flushing encoder failed\n");
        return ;
    }
    
    av_write_trailer(pFormatCtx);
    if (video_st) {
        avcodec_close(video_st->codec);
        av_free(pFrame);
        av_free(picture_buf);
    }
    avio_close(pFormatCtx->pb);
    avformat_free_context(pFormatCtx);
    fclose(in_file);
    
}

int flush_encoder(AVFormatContext *fmt_ctx,unsigned int stream_index){
    int ret;
    int got_frame;
    AVPacket enc_pkt;
    if (!(fmt_ctx->streams[stream_index]->codec->codec->capabilities &
          CODEC_CAP_DELAY))
        return 0;
    while (1) {
        enc_pkt.data = NULL;
        enc_pkt.size = 0;
        av_init_packet(&enc_pkt);
        ret = avcodec_encode_video2 (fmt_ctx->streams[stream_index]->codec, &enc_pkt,
                                     NULL, &got_frame);
        av_frame_free(NULL);
        if (ret < 0)
            break;
        if (!got_frame){
            ret=0;
            break;
        }
        printf("Flush Encoder: Succeed to encode 1 frame!\tsize:%5d\n",enc_pkt.size);
        /* mux encoded frame */
        ret = av_write_frame(fmt_ctx, &enc_pkt);
        if (ret < 0)
            break;
    }
    return ret;

}


@end
