/*
Author: Radek Jankele
Date: May 2017, update November 2019

Drift correction macro for timelapse images

	Expects Results table open containing columns "Timepoint", and pixel coordinates: "X Coordinate", "Y Coordinate", "Z coordinate"
	Aligns to the first timepoint

Requires TransformJ by Erik Meijering - Instal by updating ImageScience site
	
Start with open image (assumes two channesl)
Processing large files can fill the memory, however the script can be restarted and continues where it crashed

*/


// SETUP variables

basename=getTitle(); //define here root name of your files 
basename="aligned_sample"; //comment out if you want to preserv original file name

Ch1name = "^C1.*"; //redefine here what corresponds to your channel name (REGEX for partial match)
Ch2name = "^C2.*";
	
//By default expects GFP as the channel 1 and RFP as the channel 2

//set true to convert bit depth to 16-bit and rescale with min and max grey value set below
normalise=false;

min=0;
maxCh0=2200;
maxCh1=15000;




// The ALIGNMENT code

print("\\Clear"); // clear the log

//let user select the Output directory
out=getDirectory("Choose a Directory");
x0 =	getResult("X Coordinate", 0);
y0 =	getResult("Y Coordinate", 0);
z0 =	getResult("Z Coordinate", 0);

getDimensions(x,y,c,z,t);
if(c>1) run("Split Channels");

//Check which channels are open as separate channels
GFPexists=0;
mChExists=0;

list = getList("image.titles");
  if (list.length==0)
     print("No image windows are open");
  else {
     print("Image windows:");
     for (i=0; i<list.length; i++){
     	print(list[i]);
     	if(matches(list[i],Ch1name)){GFP=list[i]; GFPexists=1; print("GFP image open");}
     	if(matches(list[i],Ch2name)){mCh=list[i]; mChExists=1; print("mCherry image open");}
  }
}

setBatchMode(true);
GFPskip=1; 	// in case number of frames is not the same for both channels, 
			// expect that the channel with less frames was taken only every nth frame 

if(GFPexists){
	print("Got here");		
	selectImage(GFP);
	
	outCh0=out+"Ch1/";
	outCh1=out+"Ch2/";
	if(!File.exists(outCh0)) File.makeDirectory(outCh0);
	
	Stack.getDimensions(w,h,ch,sl,fr);
	
	//duplicate and save first frame - it is the reference and no translation is applied
	run("Duplicate...", "duplicate frames=1");
	
	if(normalise){
	setMinAndMax(min, maxCh0);
	run("16-bit");
	}

	saveAs("Tiff", outCh0+basename+"_t000_ch00");
	close();

GFPskip=round(nResults/fr); //calculate skipping - no skipping if both channels were acquired every frame
print(GFPskip);
}

//process the first channel
if(mChExists){
	selectImage(mCh);

	outCh1=out+"Ch2/";
	if(!File.exists(outCh1))File.makeDirectory(outCh1);
	
	run("Duplicate...", "duplicate frames=1");

	if(normalise){
		setMinAndMax(min, maxCh1);
		run("16-bit");
	}
	
	//duplicate and save first frame - it is the reference and no translation is applied
	saveAs("Tiff", outCh1+basename+"_t000_ch01");
	close();
	
	Stack.getDimensions(w,h,ch,sl,fr);
	print("slices:" +sl);
	print("frames:" +fr);

	//loop through frames and apply drift correction
	for(i=1;i<fr;i++) {
		
		t = getResult("Timepoint", i);
		x = getResult("X Coordinate", i);
		y = getResult("Y Coordinate", i);
		z = getResult("Z Coordinate", i);
	
		dx = -1*(x-x0);
		dy = -1*(y-y0);
		dz = -1*(z-z0);

		filepath=outCh1+basename+"_t"+IJ.pad(i,3)+"_ch01.tif";
		if(!File.exists(filepath)){ // if
			print("duplicating Frame: "+t);
			selectImage(mCh);
			run("Duplicate...", "title=[realigned T"+t+"] duplicate frames="+t);
			
			if(normalise){
				setMinAndMax(min, maxCh1);
				run("16-bit");
			}
		
			run("TransformJ Translate", "x-distance="+dx+" y-distance="+dy+" z-distance="+dz+" interpolation=linear voxel background=0.0");
			print(filepath);
			saveAs("Tiff", filepath);
			close("realigned T"+t);
			run("Collect Garbage");
		}
		else {
			print("Frame "+t+" is already processed");}
	}

	//convert to hyperstack
	run("Image Sequence...", "open=["+outCh1+"] increment=1 sort");
	run("Stack to Hyperstack...", "order=xyczt(default) channels=1 slices="+sl+" frames="+fr);
	saveAs("Tiff", out+basename+"_Ch2.tif");
	rename("mCh");
	//close(mCh);
}

//process the second channel if it is open
frame=GFPskip;
if(GFPexists){
	print("aligning GFP");
	selectImage(GFP);
	Stack.getDimensions(w,h,ch,sl,fr);

	for(i=1;i<fr;i++) {
		row=frame;
		
		t = getResult("Timepoint", row);
		x = getResult("X Coordinate", row);
		y = getResult("Y Coordinate", row);
		z = getResult("Z Coordinate", row);
	
		dx = -1*(x-x0);
		dy = -1*(y-y0);
		dz = -1*(z-z0);

		filepath=outCh0+basename+"_t"+IJ.pad(i,3)+"_ch00.tif";
		if(!File.exists(filepath)){
		print("Duplicated Frame: "+(i+1)+" TimePointIn mCherry: "+t+" dx: "+dx+" dy: "+dy+" dz: "+dz);
		
		selectImage(GFP);
		run("Duplicate...", "title=[realigned T"+(i+1)+"] duplicate frames="+(i+1));
			
		if(normalise){
			setMinAndMax(min, maxCh0);
			run("16-bit");
		}
		
		run("TransformJ Translate", "x-distance="+dx+" y-distance="+dy+" z-distance="+dz+" interpolation=linear voxel background=0.0");
		
		print(filepath);
		saveAs("Tiff", filepath);	
		frame=row+GFPskip;
		close("realigned T"+t);
		}
	}
		
	close(GFP);
	run("Collect Garbage");

	run("Image Sequence...", "open=["+outCh0+"] increment=1 sort");
	run("Stack to Hyperstack...", "order=xyczt(default) channels=1 slices="+sl+" frames="+fr);
	saveAs("Tiff", out+basename+"_Ch1.tif");
	GFPsaved=getTitle();
	print(GFPsaved);



	if(mChExists){	
		run("Image Sequence...", "open=["+outCh1+"] increment="+GFPskip+" sort");
		run("Stack to Hyperstack...", "order=xyczt(default) channels=1 slices="+sl+" frames="+fr);
		
		run("Merge Channels...", "c1=mCh c2=["+GFPsaved+"] create");
		saveAs("Tiff", out+basename+"_dualCh.tif");		

	}
}


setBatchMode(false);
