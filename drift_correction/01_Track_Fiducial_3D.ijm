/*
Author: Radek Jankele
Date: May 2017, update November 2019
	Macro to fit gaussian into a single maxima in a 3D timelapse (can a fiducial bead, or a polar body of the C.elegans)
	Logs 3D fitted coordinates and max intensity for each timepoint in the Results table for later use in drift correction

Start with open timelapse image (virtual stack accepted)
Expects non-saturated data
If there is multiple particles you will be prompted to draw a ROI around the one you wish to use 
Make sure your ROI contains the particle at every frame
*/

offset=18; //pixel offset for the gaussin fit selection rectangle with X and Y dimensions = 2*offset 

// Clear log and Results table
run("Clear Results");
print("\\Clear");

//Get info about the open image
getDimensions(x,y,c,z,t);
getPixelSize(unit, pxWidth, pxHeight, pxDepth); 

// In case there is multiple channels let user choose which one contains beads / nuclei
channels=newArray(c);
for(i=0;i<c;i++){
		channels[i]=toString(i+1,0);
	}

Dialog.create("3D spot tracker"); 
	Dialog.addMessage("This macro finds voxel coordinates of the brightest spot in 3D \n(e.g. C. elegans polar body)")
	Dialog.addNumber("Treshold of Noise for feature detection", 120);
	Dialog.addChoice("Select the channel", channels, 1);
	
Dialog.show();


threshold=parseInt(Dialog.getNumber());
channel=parseInt(Dialog.getChoice());

//waitForUser("Define ROI with the feature to track");

	function find3DMax(){ //Function returns 2D pixel coordinates of the maxima and pixel value
	 	getRawStatistics(nPixels, mean, min, max);
	 	run("Find Maxima...", "noise=&max output=[Point Selection]");
		getSelectionCoordinates(cx,cy);
		coord=newArray(cx[0],cy[0],max);
		return coord;
	}

	function fitGaussian(direction){
  		if(direction=="Y")setKeyDown("alt");// Set alt key down for vertical profile of a rectangular selection  	
	  	profile = getProfile();
		xValues=Array.getSequence(lengthOf(profile));
			//print(lengthOf(profile)); //debug
		Array.getStatistics(profile,min,max,mean,std);
		
		InitGuesses=newArray(min,(profile[profile.length-1]-profile [0])/(lengthOf(profile)), max-min, round(profile.length)/2, 1);
			//Array.print(InitGuesses); //debug
		Fit.doFit( "y= a+b*x+c*exp(-(x-d)*(x-d)/e) ", xValues, profile, InitGuesses);
		fx = Fit.p(3);
		return fx;
	}

setBatchMode(true)

//First, duplicate cropped imaged and load it to RAM to spead up the analysis
print("Duplicating selected ROI");
run("Duplicate...", "duplicate title=OriginalImage channels="+channel);

ori = getTitle(); //log title of original image

for(k=1;k<=t;k++) { //go through all timepoints

	selectImage(ori);
	Stack.setFrame(k);

	//Find XY maximum first
		run("Z Project...", "projection=[Max Intensity]");
		cords=find3DMax(); //find rough maximum XY
	
		print("processing timepoint: "+k);
		makeRectangle(cords[0]-offset,cords[1]-offset,2*offset,2*offset);
		
	  	//fit gaussian to get precise center coordinates
	  	xG = fitGaussian("X")+cords[0]-offset; //print("fitted X: "+xG);
	  	
	  	selectImage("MAX_OriginalImage");
	  	yG = fitGaussian("Y")+cords[1]-offset; //print("fitted Y: "+yG);
	  	
	  	close("MAX_OriginalImage");
		
	//Find maximum in XZ max projection to get the z-coordinate
		selectImage(ori);
		run("Select None");
		
		makeRectangle(xG-offset,yG-offset,2*offset,2*offset);
		run("Duplicate...", "duplicate frames="+k);

		// reslice image to display XZ plane with axial pixel size corresponding to the pxDepth from Image calibration
		run("Reslice [/]...", "output="+pxDepth+" start=Left avoid");
		run("Z Project...", "projection=[Max Intensity]");
		run("Select All");
	
		selectImage("MAX_Reslice of OriginalImage-1");
		zG = fitGaussian("Y");
		//print("fitted Z: "+zG);
	
	close("MAX_Reslice of OriginalImage-1");
	close("Reslice of OriginalImage-1");
	close("OriginalImage-1");
	
	//Write results to the table
	nR = nResults;
	setResult("Timepoint", nR, k);
	setResult("X Coordinate", nR, xG);
	setResult("Y Coordinate", nR, yG);
	setResult("Z Coordinate", nR, zG);
	setResult("Max value", nR, cords[2]);
}

setBatchMode(false);

