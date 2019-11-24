/*
Author: Radek Jankele
Date: September 2019
	Macro to segment cells from membrane images
	Pipeline starts with opended denoised image (Noise2Void or deconvolution), in case of good SNR, it works right out of the box
	This macro has been developped for segmentation of the C. elegans and therefore contains some additional features for computing embryo boundaries (mask)
	and filling cells all the way to the eggshell with Voronoi 3D. This does not work with provided sample

	Use tye channel 1 of sample_embryo_drift_correction.tif as a demo
	
	requires 3D Manager and relies on Morphological 3D segmentation from MorphoLibJ by Ignacio Arganda-Carreras and David Legland
	https://imagej.net/Morphological_Segmentation
		//select Input image option: Border Image
		//try different tollerance - start with 10 for 8-bit image
		//select advanced options to change connectivity to 26
		
	
	macro first applies filtering to close gaps in the membrane
	and then opens Morphological 3D segmentation GUI 
		to let user tinker with the "Tolerance" value to find good segmentation and review results
		it is better to oversegment and manually connect segments in the GUI
*/

//close("\\Others")
//outdir = getDirectory("Choose a Directory");

	embryoID="testE";
	baseDir="/Users/jankele/Desktop/segmentation_3D/";

	//setup your pixel size in microns
	XY=0.140;
	Z=0.75;

	//setup segmented range
	startframe=1;
	lastframe=5;

	//Do you want to save intermediate processing steps
	intermediates = true; 

	//rescale image
	scale=0.5; //downscaling laterally helps to speed up processing
	zresample=3; // oversample Z to get closer to isotropic pixels

	//
	filter_radius=3.5;

	enhance=20; //% enhancement of contrast for lateral mask segmentation
	lateralmask_method="Mean";
	
	newZ = Z/zresample;

//setting for lateral mask
	cutoff = 15;
	trim=-3;
	smooth=false;
	smoothing=12;


print("\\Clear")
//export path and folder
outdir = baseDir+embryoID+"/"+embryoID+"_segmentation/";
print(outdir);
if (File.exists(outdir)) {print("directory exists");}else {File.makeDirectory(outdir);print("directory created");}


reslice_exists=false;
scaled_exists=false;
list = getList("image.titles");
  if (list.length==0)
     print("No image windows are open");
  else {
     print("Image windows:");
     for (i=0; i<list.length; i++){
     	if(matches(list[i],"ori_scaled")){scaled_exists=true;print("original image is already open and scaled");}
     	if(matches(list[i],"ori_resliced")){reslice_exists=true;print("original image is already resliced");}
  }
}

run("3D Manager");
run("3D Manager Options", "volume surface compactness centroid_(pix) distance_to_surface surface_contact closest distance_between_centers=10 distance_max_contact=1.80 drawing=Contour");

//reslice Z and downscale
if(!scaled_exists){
	Stack.getDimensions(width, height, channels, slices, frames);
	//set proper properties to the original image 
	run("Properties...", "unit=µm pixel_width="+XY+" pixel_height="+XY+" voxel_depth="+Z+" frame=[150 sec]");
	
	run("Scale...", "x="+scale+" y="+scale+" depth="+(slices*zresample)+" interpolation=Bilinear average create title=scaled");
	rename("ori_scaled");
}

//reslice from the left to get lateral image
if(!reslice_exists){
	selectWindow("ori_scaled");
	run("Reslice [/]...", "output="+newZ+" start=Left avoid");
	rename("ori_resliced");
}

//loop over all frames
for (frame = startframe; frame < lastframe+1; frame++) {

	print("processing frame: "+frame);
	selectWindow("ori_resliced");
	Stack.setFrame(frame);

//get lateral mask
	setBatchMode(true);
	run("Duplicate...", "title=T"+frame+"_resliced duplicate frames="+frame);
//DUBUG
/*
	cutoff = 15;
	trim=-2;
	smooth=false;
	interpolation=10; //smooth segmented shape
	frame=2;
	intermediates=false;
	outdir="";
*/
	run("Duplicate...", "title=threshold duplicate frames=&frame");
	run("Enhance Contrast...", "saturated="+enhance+" process_all use");
	run("Auto Threshold", "method="+lateralmask_method+" ignore_black white stack use_stack_histogram");
	n=nSlices+1;
	
	for (i = 1; i < n; i++) {
		selectWindow("threshold");
		setSlice(i);
		run("Duplicate...", " ");

		getRawStatistics(nPixels, mean, min, max, std, histogram);
		rename("mask_"+i);
	
		if (mean>cutoff){
		
		run("Create Selection");
		run("Make Inverse");
		
		run("Convex Hull");
		
		setForegroundColor(255, 255, 255);
		setBackgroundColor(0, 0, 0);
		run("Fill", "slice");
		run("Select None");

		
		if(smooth){run("Shape Smoothing", "relative_proportion_fds=2 absolute_number_fds="+smoothing+" keep=[Absolute_number of FDs] black");}
		run("Create Selection");
		run("Make Inverse");
		run("Enlarge...", "enlarge="+trim+" pixel");
		run("Clear Outside", "slice");

		selectWindow("T"+frame+"_resliced");
		setSlice(i);
		run("Restore Selection");
		run("Draw", "slice");
		run("Select None");
		}
		else {
			run("Select All");
			run("Clear");
		}
	}
	selectWindow("T"+frame+"_resliced");
	if(intermediates)saveAs("Tiff", outdir+"T"+frame+"_lateral_outlines.tif");

	run("Images to Stack", "name=[T"+frame+"_lateral_mask] title=mask_ use");
	saveAs("Tiff", outdir+"T"+frame+"_lateral_mask.tif");
	rename("T"+frame+"_lateral_mask");
	
//segment original scaled image

	print("segmenting frame: "+frame);
	selectWindow("ori_scaled");
	Stack.setFrame(frame);
	run("Duplicate...", "title=T"+frame+"_scaled duplicate frames="+frame);

	selectWindow("T"+frame+"_scaled");
	run("Morphological Filters (3D)", "operation=Closing element=Ball x-radius="+filter_radius+" y-radius="+filter_radius+" z-radius="+(filter_radius/2.5));
	ori = getTitle();
	
	newname = "T"+frame+"_filtered";
	if(intermediates)saveAs("Tiff", outdir+newname+".tif");
	rename(newname+".tif");
	setBatchMode(false);
	
	run("Morphological Segmentation");
	
	waitForUser("process images and export the resulting basins and overlay before continuing");
	selectWindow("Morphological Segmentation");

	if(intermediates){
		call("inra.ijpb.plugins.MorphologicalSegmentation.setDisplayFormat", "Overlaid basins");
		call("inra.ijpb.plugins.MorphologicalSegmentation.createResultImage");
		saveAs("Tiff", outdir+"T"+frame+"_overlay.tif"); close();
	}
	
	selectWindow("Morphological Segmentation");
		call("inra.ijpb.plugins.MorphologicalSegmentation.setDisplayFormat", "Catchment basins");
		call("inra.ijpb.plugins.MorphologicalSegmentation.createResultImage");
		rename("watershed");
		close("Morphological Segmentation");
	
	setBatchMode(true);
	
	selectWindow("watershed");
	run("Grays");
	run("8-bit");
	run("Gray Morphology", "radius=1 type=circle operator=dilate");
	if(intermediates){saveAs("Tiff", outdir+"T"+frame+"_interm.segmentation.tif");}
	rename("T"+frame+"_segmented");

	//masking the segmentation
	open(outdir+"T"+frame+"_lateral_mask.tif");
	//mask was produced from the side view >> smooth the outlines from the top-view

		run("Reslice [/]...", "start=Top rotate avoid");


		sl = nSlices;
		run("Options...", "iterations=5 count=2 black pad do=Close stack");
		for (i = 0; i < sl; i++) {
			
			setSlice(i+1);
			getRawStatistics(nPixels, mean);

			if(mean>0){
				run("Create Selection");
				run("Make Inverse");
				
				getStatistics(area);
				//print(area);
				if(area>(16*cutoff)){	
					run("Interpolate", "interval=5 smooth adjust");
					run("Interpolate", "interval=8 smooth adjust");
					run("Clear Outside", "slice");
					setForegroundColor(255, 255, 255);
					run("Fill", "slice");
					run("Select None");		
				} else {
					//print("smaller");
					run("Select All");		
					run("Clear", "slice");
					run("Select None");		
				}
			}
		}
	run("Select None");		
	run("Invert", "stack");

	//add mask to the 3D manager
		run("3D Manager");
		Ext.Manager3D_SelectAll();
		Ext.Manager3D_Delete();
		Ext.Manager3D_AddImage();

	//add the mask to the segmented image
	selectWindow("T"+frame+"_segmented");
	
	run("Macro...", "code=if(v==255)v=254 stack");
	
	//delete what overflows
	run("3D Manager");
		Ext.Manager3D_Select(0);
		Ext.Manager3D_FillStack(2, 2, 2);
		Ext.Manager3D_Delete();

	//fill undersegmented parts of the embryo with 3D voronoi
	run("3D Watershed Voronoi", "radius_max=0");
	print("computing voronoi to the mask");
	selectWindow("VoronoiZones");
	run("Macro...", "code=if(v==2)v=0 stack");
	run("8-bit");

	
		newXY=XY/scale;
		
	run("Properties...", "unit=µm pixel_width="+newXY+" pixel_height="+newXY+" voxel_depth="+newZ+" frame=[150 sec]");
	saveAs("Tiff", outdir+"T"+frame+"_segmented.tif");
	//print("got here");

	run("3D Manager");
		Ext.Manager3D_AddImage();
		Ext.Manager3D_SelectAll();
		Ext.Manager3D_Measure();
		Ext.Manager3D_SaveResult("M", outdir+"T"+frame+"_volumes.csv");
		print("Measurements saved");
		Ext.Manager3D_CloseResult("M");
	//print("got here");

	setBatchMode(false);

	//remove intermediate mask
	if(!intermediates) File.delete(outdir+"T"+frame+"_lateral_mask.tif");

	close("*T"+frame+"*");
	print("\\Clear");
	print("segmentation of the frame " +frame+ " completed");
	run("Collect Garbage");
	
}
print("segmentation pipeline completed");