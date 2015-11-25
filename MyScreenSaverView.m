/*	File:		MyScreenSaverView.c		Description: A simple Screen Saver module which uses the Sequence Grabber 	             DataProc mung technique first demonstrated in samples like MungGrab by km.				 This sample is for 10.3 only and uses the vImage library to perform some				 very basic pixel munging producing an effect familiar to anyone who remembers                 the 1960's (or an Austin Powers movie). A good enhancement would be to have some                 Hendrix or maybe early Floyd playing in the background. Enjoy!	Author:		era	Copyright: 	� Copyright 2003 Apple Computer, Inc. All rights reserved.		Disclaimer:	IMPORTANT:  This Apple software is supplied to you by Apple Computer, Inc.				("Apple") in consideration of your agreement to the following terms, and your				use, installation, modification or redistribution of this Apple software				constitutes acceptance of these terms.  If you do not agree with these terms,				please do not use, install, modify or redistribute this Apple software.				In consideration of your agreement to abide by the following terms, and subject				to these terms, Apple grants you a personal, non-exclusive license, under Apple�s				copyrights in this original Apple software (the "Apple Software"), to use,				reproduce, modify and redistribute the Apple Software, with or without				modifications, in source and/or binary forms; provided that if you redistribute				the Apple Software in its entirety and without modifications, you must retain				this notice and the following text and disclaimers in all such redistributions of				the Apple Software.  Neither the name, trademarks, service marks or logos of				Apple Computer, Inc. may be used to endorse or promote products derived from the				Apple Software without specific prior written permission from Apple.  Except as				expressly stated in this notice, no other rights or licenses, express or implied,				are granted by Apple herein, including but not limited to any patent rights that				may be infringed by your derivative works or by other works in which the Apple				Software may be incorporated.				The Apple Software is provided by Apple on an "AS IS" basis.  APPLE MAKES NO				WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED				WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A PARTICULAR				PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN				COMBINATION WITH YOUR PRODUCTS.				IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR				CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE				GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)				ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION AND/OR DISTRIBUTION				OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER THEORY OF CONTRACT, TORT				(INCLUDING NEGLIGENCE), STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN				ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.					Change History (most recent first): <1> 10/28/03 initial release*/#import "MyScreenSaverView.h"#include <Accelerate/Accelerate.h>#define Log(X, Y) { fprintf(stderr," %s self=%#x\n", X, (unsigned int)Y); }#define LogErr(X, Y) { if (X != noErr) { fprintf(stderr,"error: %ld", (long)X); Log(Y, self); }}#define BailErr(X, Y) { if (X != noErr) { LogErr(X, Y); goto bail; } }// globalsstatic UInt8 OwnsHardware = 0;static SeqGrabComponent SeqGrab = 0; // the sequence grabber componentstatic Component *PanelListPtr = NULL;static UInt8 NumberOfPanels = 0;static UInt8 Index = 0;static Pixel_8 RedTable[256], GreenTable[256], BlueTable[256];// MungPixels uses vImage to transform the source before it is drawn to the screen// http://developer.apple.com/documentation/Performance/Conceptual/vImage/index.htmlstatic vImage_Error MungPixels(const GWorldPtr inGWorld) {    vImage_Buffer srcVImageBuffer, dstVImageBuffer;     PixMapHandle hPixMap = GetGWorldPixMap(inGWorld);     void		 *pPixels= GetPixBaseAddr(hPixMap);     long		 rowBytes = GetPixRowBytes(hPixMap); 		Rect bounds;	vImage_Error vIError;		GetPortBounds(inGWorld, &bounds);         srcVImageBuffer.data = pPixels + (bounds.top * rowBytes) + (bounds.left * GetPixDepth(hPixMap) / 8); // pointer to the top left pixel of the buffer     srcVImageBuffer.height = bounds.bottom - bounds.top;												 // the height (in pixels) of the buffer     srcVImageBuffer.width = bounds.right - bounds.left;													 // the width (in pixels) of the buffer     srcVImageBuffer.rowBytes = rowBytes;																 // the number of bytes in a pixel row     dstVImageBuffer = srcVImageBuffer;																	 // src and dest buffer are the same	// transforms an ARGB8888 image by replacing all pixels of a given color with pixels	// of a new color using separate look-up tables to replace each of the four components   vIError = vImageTableLookUp_ARGB8888(&srcVImageBuffer, &dstVImageBuffer, NULL, RedTable, GreenTable, BlueTable, kvImageLeaveAlphaUnchanged);		// mess with the tables for next time	RedTable[Index++] ^= 0x80;	GreenTable[Index++] ^= 0xA0;	BlueTable[Index++] ^= 0x50;		return vIError;}// SGDataProc callbackstatic pascal OSErr mySGDataProc(SGChannel c, Ptr p, long len, long *offset, long chRefCon, TimeValue time, short writeType, long refCon){#pragma unused(offset,chRefCon,time,writeType)		CodecFlags ignore;	OSErr err = paramErr;		MyScreenSaverView *myViewObject = (MyScreenSaverView *)refCon;	if (NULL == myViewObject) { Log("myViewObject NULL!", myViewObject); return err; }		err = DecompressSequenceFrameS([myViewObject decoSeq],	// sequence ID returned by DecompressSequenceBegin									p,						// pointer to compressed image data									len,					// size of the buffer									0,					    // in flags									&ignore,				// out flags									NULL);					// sync ie. no async completion proc										if (err) { Log("decoSeq", myViewObject); return err; }		err = MungPixels([myViewObject offscreen]);	if (err) { Log("MungPixels", myViewObject); return err; }		[myViewObject lockFocus];		err = DecompressSequenceFrameS([myViewObject drawSeq],	// sequence ID returned by DecompressSequenceBegin								   [myViewObject baseAddr], // pointer to data								   [myViewObject length],   // size of the buffer								   0,					    // in flags								   &ignore,				    // out flags								   NULL);					// sync ie. no async completion proc		if (err) Log("drawSeq", myViewObject);		[myViewObject unlockFocus];		return err;}@implementation MyScreenSaverView- (id)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview{	NSRect bounds;		    // init da super	self = [super initWithFrame:frame isPreview:isPreview];		Log("\pInitializing ScreenSaver", self);    	if (self) {		// grab the screensaver defaults		mBundleID = [[NSBundle bundleForClass:[self class]] bundleIdentifier];		ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:mBundleID];				// try to load the version key, used to see if we have any saved settings		mVersion = [defaults floatForKey:@"version"];		if (!mVersion) {			// no previous settings so define our defaults			mVersion = 1;			mUseHighQuality = NO;			mMirrorCheckbox = NO;						// write out the defaults			[defaults setInteger:mVersion forKey:@"version"];			[defaults setInteger:mUseHighQuality forKey:@"useHighQuality"];			[defaults setInteger:mMirror forKey:@"mirror"];						// synchronize			[defaults synchronize];		}		// set defaults...		mUseHighQuality = [defaults integerForKey:@"useHighQuality"];		mMirror = [defaults integerForKey:@"mirror"];				//...first time though mUserData may be 0 which is fine		[self newUserData:&mUserData fromDefaults:defaults];				mIsPreview = isPreview;				// create our quickdraw view for the sequence grabber		mQDView = [[NSQuickDrawView alloc] initWithFrame:NSZeroRect];        if (!mQDView) {            [self autorelease];            BailErr(paramErr, "[NSQuickDrawView alloc]");        }        		// make sure the subview resizes        [self setAutoresizesSubviews:YES];		[self addSubview:mQDView];        [mQDView release];				bounds = [self bounds];				SetRect(&mWindowBounds, (SInt16)NSMinX(bounds), (SInt16)NSMinY(bounds),                                (SInt16)NSMaxX(bounds), (SInt16)NSMaxY(bounds));				// set up the sequence grabber for all instances		if (!OwnsHardware++) {			ComponentDescription cd = { SeqGrabPanelType, VideoMediaType, 0, 0, 0 };			Component			 c = 0;			Component 			 *cPtr = NULL;			ComponentResult      err;			int					 index;						Log("\pOpened Sequence Grabber", self);			// initialize the movie toolbox			err = EnterMovies();			BailErr(err, "EnterMovies");						// open the sequence grabber component and initialize it			err = OpenADefaultComponent(SeqGrabComponentType, 0, &SeqGrab);			BailErr(err, "OpenADefaultComponent");						err = SGInitialize(SeqGrab);			BailErr(err, "SGInitialize");						// tell the SG we're not making a movie			err = SGSetDataRef(SeqGrab, 0, 0, seqGrabDontMakeMovie | seqGrabDataProcIsInterruptSafe);			BailErr(err, "SGSetDataRef");						// 'safe' GWorld - we don't actually draw anything here			err = SGSetGWorld(SeqGrab, NULL, NULL);			BailErr(err, "SGSetGWorld");			// set up the settings panel list removing the "Compression" panel			NumberOfPanels = CountComponents(&cd);			if (NumberOfPanels == 0) BailErr(paramErr, "CountComponents");						PanelListPtr = (Component *)NewPtr(sizeof(Component) * (NumberOfPanels + 1));			if (err = MemError() || NULL == PanelListPtr) BailErr(err, "PanelListPtr");						cPtr = PanelListPtr;			NumberOfPanels = 0;			do {				ComponentDescription compInfo;				c = FindNextComponent(c, &cd);				if (c) {					Handle hName = NewHandle(0);					if (err = MemError() || NULL == hName) BailErr(err, "NewHandle");										GetComponentInfo(c, &compInfo, hName, NULL, NULL);					if (PLstrcmp(*hName, "\pCompression") != 0) {						*cPtr++ = c;						NumberOfPanels++;					}					DisposeHandle(hName);				}			} while (c);			 			// init the color tables for munging			for (index = 0; index < 256; index++) {							RedTable[index] = index;				GreenTable[index] = index;				BlueTable[index] = index;			}						// if we can't get a channel at this point we're probaby already in use			// by some other process so we're not going to be able to work anyway			err = SGNewChannel(SeqGrab, VideoMediaType, &mSGChanVideo);			BailErr(err, "SGNewChannel");		}		// set the animation time interval, animateOneFrame is called 60 times a second        [self setAnimationTimeInterval:1/60.0];				return self;    }	bail:	return nil;}- (void)dealloc{	OSErr err;		if (--OwnsHardware == 0) {		// when completely finished with all instances		// make sure to dispose of everything correctly		err = CloseComponent(SeqGrab);		DisposePtr((Ptr)PanelListPtr);		ExitMovies();				Log("\pClosed Sequence Grabber", self);	}		Log("\pDeallocating ScreenSaver", self);			[super dealloc];}- (BOOL)isFlipped{    return YES;}- (void)startAnimation{	ImageDescriptionHandle desc = NULL; // an image description	ComponentResult err;		[super startAnimation];		Log("\pStart Animation", self);		if ([mQDView qdPort] == NULL) {		// the first time lockFocus is called on the NSQuickDrawView		// it creates a valid qdPort - we need this to draw into and		// before this is done, qdPort is NULL		[mQDView lockFocus];		[mQDView unlockFocus];		Log("\pCreated qdport", self);	}		if (mSGChanVideo == 0) {		// create a new sequence grabber video channel		err = SGNewChannel(SeqGrab, VideoMediaType, &mSGChanVideo);		BailErr(err, "SGNewChannel");	}		// set to record, we've already told SG we're not making a movie	err = SGSetChannelUsage(mSGChanVideo, seqGrabRecord | seqGrabLowLatencyCapture);	BailErr(err, "SGSetChannelUsage");		// this will return the video digitizer's active source rectangle	err = SGGetSrcVideoBounds(mSGChanVideo, &mSourceBounds);	BailErr(err, "SGGetSrcVideoBounds");		// set the channel bounds to either the full active source rectangle	// or to whatever the default size is, ignore error first time	SGSetChannelBounds(mSGChanVideo, &mSourceBounds);		// if we have some user channel settings, set them now	if (mUserData) SGSetChannelSettings(SeqGrab, mSGChanVideo, mUserData, 0);	// get the channels image description	desc = (ImageDescriptionHandle)NewHandle(0);	if (err = MemError() || NULL == desc) BailErr(err, "NewHandle");	err = SGPrepare(SeqGrab, false, true);	BailErr(err, "SGPrepare");		err = SGGetChannelSampleDescription(mSGChanVideo, (Handle)desc);	BailErr(err, "SGGetChannelSampleDescription");		// grab the native capture size from the Image Description	// and really set the channel bounds to this size	mSourceBounds.bottom = (*desc)->height;	mSourceBounds.right = (*desc)->width;		err = SGSetChannelBounds(mSGChanVideo, &mSourceBounds);	BailErr(err, "SGSetChannelBounds");		// create a 32-bit offscreen to decompress into	err = QTNewGWorld(&mOffscreen, k32ARGBPixelFormat, &mSourceBounds, NULL, NULL, pixelsLocked);	BailErr(err, "QTNewGWorld");		// to make the SG happy	err = SGSetGWorld(SeqGrab, mOffscreen, NULL);	BailErr(err, "SGSetGWorld");		// save the baseAddr for later	mBaseAddr = GetPixBaseAddr(GetPortPixMap(mOffscreen));		// set up the SGDataProc callback	mSGDataUPP = NewSGDataUPP(&mySGDataProc);	if (mSGDataUPP == NULL) BailErr(paramErr, "NewSGDataUPP");		err = SGSetDataProc(SeqGrab, mSGDataUPP, (long)self);	BailErr(err, "SGSetDataProc");		// start recording	err = SGStartRecord(SeqGrab);	LogErr(err, "SGStartRecord");		if (mDecoSeq == 0) {				// set up decompression sequence - DataProc to offscreen		CodecFlags cFlags = (mUseHighQuality && !mIsPreview) ? codecHighQuality : codecNormalQuality;				err = DecompressSequenceBeginS(&mDecoSeq,					// pointer to field to receive unique ID for sequence									   desc,						// handle to image description structure									   NULL,						// points to the compressed image data									   0,                   		// size of the data buffer									   mOffscreen,	        		// port for the DESTINATION image									   NULL,						// graphics device handle, if port is set, set to NULL									   NULL,						// decompress the entire source image - no source extraction									   NULL,						// transformation matrix									   srcCopy,						// transfer mode specifier									   (RgnHandle)NULL,				// clipping region in dest. coordinate system to use as a mask									   0,							// flags									   cFlags, 						// accuracy in decompression									   bestSpeedCodec);				// compressor identifier or special identifiers ie. bestSpeedCodec				LogErr(err, "DecompressSequenceBeginS decoSeq");	}		if (mDrawSeq == 0) {				// set up draw sequence - offscreen to NSQuickDrawView		MatrixRecord scaleMatrix;		Rect		 tempBounds = mWindowBounds;				// always scale and mirror if user wants to		if (mMirror) {			tempBounds.left = mWindowBounds.right;			tempBounds.right = mWindowBounds.left;		}				RectMatrix(&scaleMatrix, &mSourceBounds, &tempBounds);				// dispose of the channel image description and get the offscreen pixmap image description		DisposeHandle((Handle)desc); desc = NULL;		err = MakeImageDescriptionForPixMap(GetPortPixMap(mOffscreen), &desc);		BailErr(err, "MakeImageDescriptionForPixMap");		// remember the data length		mLen = ((*desc)->height * (*desc)->width) * 4;				err = DecompressSequenceBeginS(&mDrawSeq,					// pointer to field to receive unique ID for sequence									   desc,						// handle to image description structure									   mBaseAddr,					// points to the image data									   mLen,                   		// size of the data buffer									   [mQDView qdPort],	        // port for the DESTINATION image									   NULL,						// graphics device handle, if port is set, set to NULL									   NULL,						// decompress the entire source image - no source extraction									   &scaleMatrix,				// transformation matrix									   srcCopy,						// transfer mode specifier									   (RgnHandle)NULL,				// clipping region in dest. coordinate system to use as a mask									   0,							// flags									   codecNormalQuality, 			// accuracy in decompression									   bestSpeedCodec);				// compressor identifier or special identifiers ie. bestSpeedCodec				BailErr(err, "DecompressSequenceBeginS drawSeq");				// tell the sequence to flush		SetDSequenceFlags(mDrawSeq, codecDSequenceFlushInsteadOfDirtying, codecDSequenceFlushInsteadOfDirtying);	}	bail:	// dispose of the Image Description we have	if (desc) DisposeHandle((Handle)desc);}- (void)stopAnimation{	ComponentResult err;	    [super stopAnimation];		Log("\pStop Animation", self);		// stop the sequence grabber	err = SGStop(SeqGrab);	LogErr(err, "SGStop");		// if we have a valid channel toss it	if (mSGChanVideo) {		err = SGDisposeChannel(SeqGrab, mSGChanVideo);		mSGChanVideo = 0;		LogErr(err, "SGDisposeChannel");	}		// remove the dataproc	err = SGSetDataProc(SeqGrab, NULL, NULL);	LogErr(err, "SGSetDataProc");	DisposeSGDataUPP(mSGDataUPP);		// release the sequence grabber	err = SGRelease(SeqGrab);	LogErr(err, "SGRelease");		// close down the sequences	err = CDSequenceEnd(mDecoSeq);	mDecoSeq = 0;	LogErr(err, "CDSequenceEnd");		err = CDSequenceEnd(mDrawSeq);	mDrawSeq = 0;	LogErr(err, "CDSequenceEnd");		// change to 'safe' gworld before we toss the offscreen	err = SGSetGWorld(SeqGrab, NULL, NULL);	LogErr(err, "SGSetGWorld");	if (mOffscreen) DisposeGWorld(mOffscreen);}- (void)animateOneFrame{	ComponentResult err;		// sequence grabber do some work	err = SGIdle(SeqGrab);	LogErr(err, "SGIdle");	if (err) [self stopAnimation];}- (BOOL)hasConfigureSheet{    return YES;}// Display the configuration sheet for the user to choose their settings- (NSWindow*)configureSheet{	// if we haven't loaded our configure sheet, load the nib named MyScreenSaver.nib	if (!mConfigureSheet)		[NSBundle loadNibNamed:@"MyScreenSaver" owner:self];	// set the UI state	[mUseHQCheckbox setState:mUseHighQuality];	[mMirrorCheckbox setState:mMirror];    	return mConfigureSheet;}// Called when the user clicked the SAVE button- (IBAction) closeSheetSave:(id) sender{    // get the defaults	ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:mBundleID];	// save the UI state	mUseHighQuality = [mUseHQCheckbox state];	mMirror = [mMirrorCheckbox state];		// write the defaults	[defaults setInteger:mUseHighQuality forKey:@"useHighQuality"];	[defaults setInteger:mMirror forKey:@"mirror"];		[self saveUserData:mUserData toDefaults:defaults];		// synchronize    [defaults synchronize];	// end the sheet    [NSApp endSheet:mConfigureSheet];}// Called when th user clicked the CANCEL button- (IBAction) closeSheetCancel:(id) sender{	// nothing to configure    [NSApp endSheet:mConfigureSheet];}// Called when th user clicked the Configure button// NOTE: There is a know bug in QuickTime 6.4 in which the// Settings Dialog pops up in random locations...sigh...- (IBAction) sgConfigurationDialog:(id) sender{	OSErr err;	SGChannel tempChannel;		// create a temporary video channel	err = SGNewChannel(SeqGrab, VideoMediaType, &tempChannel);	BailErr(err, "SGNewChannel");		err = SGSetChannelUsage(tempChannel, seqGrabRecord | seqGrabLowLatencyCapture);	BailErr(err, "SGSetChannelUsage");	SGSetChannelBounds(tempChannel, &mSourceBounds);		// set the previous settings, bring up the dialog and if the user didn't cancel	// save the new channel settings for later	if (mUserData) SGSetChannelSettings(SeqGrab, tempChannel, mUserData, 0);	 	err = SGSettingsDialog(SeqGrab, tempChannel, NumberOfPanels, PanelListPtr, 0, NULL, NULL);	if (noErr == err) {		// dispose the old settings and get the new channel settings		if (mUserData) DisposeUserData(mUserData);		err = SGGetChannelSettings(SeqGrab, tempChannel, &mUserData, 0);		LogErr(err, "SGGetChannelSettings");	} else if (userCanceledErr != err) {		LogErr(err, "SGSettingsDialog");	}	bail:	if (tempChannel) SGDisposeChannel(SeqGrab, tempChannel);}// Get the Channel Settings as UserData from the preferences-(OSErr)newUserData:(UserData *)outUserData fromDefaults:(ScreenSaverDefaults *)inDefaults{	NSData   *theSettings;	Handle   theHandle = NULL;	UserData theUserData = NULL;	OSErr    err = paramErr;		// read the new setttings from our preferences	theSettings = [inDefaults objectForKey:@"sgVideoSettings"];		if (theSettings) {		err = PtrToHand([theSettings bytes], &theHandle, [theSettings length]);				if (theHandle) {			err = NewUserDataFromHandle(theHandle, &theUserData);			if (theUserData) {				*outUserData = theUserData;			}			DisposeHandle(theHandle);		}	}  return err;}// Save the Channel Settings from UserData in the preferences-(OSErr)saveUserData:(UserData)inUserData toDefaults:(ScreenSaverDefaults *)inDefaults;{	NSData *theSettings;	Handle hSettings;	OSErr  err;		if (NULL == inUserData) return paramErr;		hSettings = NewHandle(0);	err = MemError();		if (noErr == err) {		err = PutUserDataIntoHandle(inUserData, hSettings); 				if (noErr == err) {			HLock(hSettings);			theSettings = [NSData dataWithBytes:(UInt8 *)*hSettings length:GetHandleSize(hSettings)];						// save the new setttings to our preferences			if (theSettings) {				[inDefaults setObject:theSettings forKey:@"sgVideoSettings"];				[inDefaults synchronize];			}		}				DisposeHandle(hSettings);	}		return err;}// getters-(ImageSequence)decoSeq{    return mDecoSeq;}-(ImageSequence)drawSeq{    return mDrawSeq;}-(GWorldPtr)offscreen;{	return mOffscreen;}-(Ptr)baseAddr;{	return mBaseAddr;}-(UInt32)length{	return mLen;}@end