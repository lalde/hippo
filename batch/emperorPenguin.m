
% Create Excel worksheet containing all selected measures for a given experiment.
%
%   USAGE
%       emperorPenguin
%
%   SEE ALSO
%       emperorSettings emperorHeadings createEmperorArray missingClusterData
%       excelStitch addCellNums kingPenguin
%
% Written by BRK 2014

function emperorPenguin

tic

%% get globals
global penguinInput arena mapLimits dSmoothing dBinWidth dMinBins clusterFormat
if isempty(penguinInput)
    startup
end

%% select folders to analyze
folders = uipickfilesBRK();
if ~iscell(folders); return; end;

%% choose what to calculate
[include,OK] = emperorSettings();
if OK == 0; return; end;

%% get experiment details
prompt={'How many sessions per experiment?'};
name='Sessions/experiment';
numlines=1;
defaultanswer={'3'};
Answers = inputdlg(prompt,name,numlines,defaultanswer,'on');
if isempty(Answers); return; end;
seshPerExp = str2double(Answers{1});
ccComps = nchoosek(1:seshPerExp,2);

%% rate map settings
prompt={'Smoothing (# of bins)','Spatial bin width (cm)','Mininum occupancy'};
name='Map settings';
numlines=1;
defaultanswer={num2str(dSmoothing),num2str(dBinWidth),'0'};
Answers = inputdlg(prompt,name,numlines,defaultanswer,'on');
if isempty(Answers); return; end;
smooth = str2double(Answers{1});
binWidth = str2double(Answers{2});
minTime = str2double(Answers{3});

%% find field settings
if include.fields
    prompt={'Threshold for including surrounding bins (included if > thresh*peak)','Minimum bins for a field','Minimum peak rate for a field (Hz?)'};
    name='Find field settings';
    numlines=1;
    defaultanswer={'0.2',num2str(dMinBins),'1'};
    Answers = inputdlg(prompt,name,numlines,defaultanswer,'on');
    if isempty(Answers); return; end;
    fieldThresh = str2double(Answers{1});
    minBins = str2double(Answers{2});
    minPeak = str2double(Answers{3});
end

%% grid stats settings
if include.grid
    prompt={'Normalized threshold value used to search for peaks on the autocorrelogram (0:1)'};
    name='Grid stats settings';
    numlines=1;
    defaultanswer={'0.2'};
    Answers = inputdlg(prompt,name,numlines,defaultanswer,'on');
    if isempty(Answers); return; end;
    gridThresh = str2double(Answers{1});
    if gridThresh < 0 || gridThresh > 1
        gridThresh = 0.2;
        display('Grid threshold value out of range, using default 0.2.')
    end
end

%% object settings
if include.obj
    [file,path] = uigetfile('*.mat','Choose object locations');
    load(fullfile(path,file))
end

%% excel output folder
excelFolder = uigetdir('','Choose folder for the Excel output');
if excelFolder == 0; return; end;
dt = datestr(clock,30);
ending = ['\emperor' sprintf('%s.xlsx',dt)];
fullName = [excelFolder ending];

%% column headers
colHeaders = emperorHeadings(include,ccComps);

%% compute stats for each folder
for iFolder = 1:length(folders)
    display(sprintf('Folder %d of %d',iFolder,length(folders)))
    
    %% check all sessions in experiment for clusters in case some are only present in certain sessions
    expNum = ceil(iFolder/seshPerExp);
    if mod(iFolder,seshPerExp) == 1
        cellMatrix = [];
        for jFolder = iFolder:(iFolder+(seshPerExp-1))
            writeInputBNT(penguinInput,folders{1,jFolder},arena,clusterFormat)
            data.loadSessions(penguinInput);
            cellMatrix = [cellMatrix; data.getCells];
        end
        sortedMat = sortrows(cellMatrix);
        cellMatrix = unique(sortedMat,'rows');
        numClusters = size(cellMatrix,1);
    end
    
    %% get positions, spikes, map, and rates
    writeInputBNT(penguinInput,folders{1,iFolder},arena,clusterFormat)
    data.loadSessions(penguinInput);
    posAve = data.getPositions('speedFilter',[2 0]);
    posT = posAve(:,1);
    posX = posAve(:,2);
    posY = posAve(:,3);
    
    %% extract necessary measures that don't rely on clusters to save time
    if include.HD
        pos = data.getPositions('average','off','speedFilter',[2 0]);
        allHD = analyses.calcHeadDirection(pos);
    end
    if include.speed
        Speed = general.speed(posAve);
    end
    
    %% loop through all cells
    for iCluster = 1:numClusters
        display(sprintf('Cluster %d of %d',iCluster,numClusters))
        
        clusterData(iCluster,iFolder,expNum).folder = folders{1,iFolder};
        clusterData(iCluster,iFolder,expNum).tetrode = cellMatrix(iCluster,1);
        clusterData(iCluster,iFolder,expNum).cluster = cellMatrix(iCluster,2);
        %% general calculations
        spikes = data.getSpikeTimes([cellMatrix(iCluster,1) cellMatrix(iCluster,2)]);       
        if isempty(spikes)   % cluster is missing in this session, fill array with nans
            clusterData = missingClusterData(clusterData,iCluster,iFolder,expNum,include);
            
        else   % we have spikes, continue as usual
            map = analyses.map([posT posX posY],spikes,'smooth',smooth,'binWidth',binWidth,'minTime',minTime,'limits',mapLimits);
            clusterData(iCluster,iFolder,expNum).rateMap = map.z;
            clusterData(iCluster,iFolder,expNum).countMap = map.count;
            meanRate = analyses.meanRate(spikes,posAve);
            clusterData(iCluster,iFolder,expNum).meanRate = meanRate;
            if ~isfield(map,'peakRate')
                peakRate = 0;
            else
                peakRate = map.peakRate;
            end
            clusterData(iCluster,iFolder,expNum).peakRate = peakRate;
            totalSpikes = length(spikes);
            clusterData(iCluster,iFolder,expNum).totalSpikes = totalSpikes;
            %% cluster quality
            [quality,L_ratio,isoDist] = loadQualityInfo(folders{1,iFolder},cellMatrix(iCluster,1),cellMatrix(iCluster,2));
            clusterData(iCluster,iFolder,expNum).quality = quality;
            clusterData(iCluster,iFolder,expNum).L_ratio = L_ratio;
            clusterData(iCluster,iFolder,expNum).isoDist = isoDist;
            %% spike width
            if include.spikeWidth
                try
                    spikeWidth = halfMaxWidth(folders{1,iFolder},cellMatrix(iCluster,1),spikes);
                catch
                    spikeWidth = nan;
                end
                clusterData(iCluster,iFolder,expNum).spikeWidth = spikeWidth;
            end
            
            %% descriptive stats
            if include.sss
                [info,spars,sel] = analyses.mapStatsPDF(map);
                clusterData(iCluster,iFolder,expNum).spatInfo = info.content;
                clusterData(iCluster,iFolder,expNum).sparsity = spars;
                clusterData(iCluster,iFolder,expNum).selectivity = sel;
            end
            if include.coherence
                Coherence = analyses.coherence(map.z);
                clusterData(iCluster,iFolder,expNum).coherence = Coherence;
            end
            
            %% field stats and border scores
            if include.fields
                [fieldsMap,fields] = analyses.placefield(map,'threshold',fieldThresh,'binWidth',binWidth,'minBins',minBins,'minPeak',minPeak);
                if ~isempty(fields)
                    fieldNum = length(fields);
                    sizes = nan(1,50);
                    for iField = 1:length(fields)
                        sizes(iField) = fields(1,iField).size;
                    end
                    biggestField = find(sizes == nanmax(sizes));
                    fieldMean = nanmean(sizes);
                    fieldMax = nanmax(sizes);
                    fieldCOMx = fields(1,biggestField).x;
                    fieldCOMy = fields(1,biggestField).y;
                    if ~isempty(fieldsMap)
                        border = analyses.borderScore(map.z,fieldsMap,fields);
                    else
                        border = nan;
                    end
                else
                    fieldNum = 0;
                    fieldMean = nan;
                    fieldMax = nan;
                    fieldCOMx = nan;
                    fieldCOMy = nan;
                    border = nan;
                end
                clusterData(iCluster,iFolder,expNum).fieldNum = fieldNum;
                clusterData(iCluster,iFolder,expNum).fieldMean = fieldMean;
                clusterData(iCluster,iFolder,expNum).fieldMax = fieldMax;
                clusterData(iCluster,iFolder,expNum).COMx = fieldCOMx;
                clusterData(iCluster,iFolder,expNum).COMy = fieldCOMy;
                clusterData(iCluster,iFolder,expNum).border = border;
            end
            
            %% grid statistics
            if include.grid
                autoCorr = analyses.autocorrelation(map.z);
                try
                    [score,stats] = analyses.gridnessScore(autoCorr,'threshold',gridThresh);
                    if ~isempty(stats.spacing)
                        gridScore = score;
                        gridSpacing = mean(stats.spacing);
                        gridOrientation1 = stats.orientation(1);
                        gridOrientation2 = stats.orientation(2);
                        gridOrientation3 = stats.orientation(3);
                    else
                        gridScore = nan;
                        gridSpacing = nan;
                        gridOrientation1 = nan;
                        gridOrientation2 = nan;
                        gridOrientation3 = nan;
                    end
                catch
                    gridScore = nan;
                    gridSpacing = nan;
                    gridOrientation1 = nan;
                    gridOrientation2 = nan;
                    gridOrientation3 = nan;
                end
                clusterData(iCluster,iFolder,expNum).gridScore = gridScore;
                clusterData(iCluster,iFolder,expNum).gridSpacing = gridSpacing;
                clusterData(iCluster,iFolder,expNum).gridOrient1 = gridOrientation1;
                clusterData(iCluster,iFolder,expNum).gridOrient2 = gridOrientation2;
                clusterData(iCluster,iFolder,expNum).gridOrient3 = gridOrientation3;
            end
            
            %% head direction
            if include.HD
                [spikePos,spkInd] = data.getSpikePositions(spikes,posAve);
                try
                    spkHDdeg = analyses.calcHeadDirection(pos(spkInd,:));
                    tc = analyses.turningCurve(spkHDdeg,allHD,data.sampleTime,'binWidth',6);
                    tcStat = analyses.tcStatistics(tc,6,20);
                    vLength = tcStat.r;
                    meanAngle = tcStat.mean;
                catch
                    vLength = nan;
                    meanAngle = nan;
                end
                clusterData(iCluster,iFolder,expNum).mvl = vLength;
                clusterData(iCluster,iFolder,expNum).angle = meanAngle;
            end
            
            %% speed
            if include.speed
                if ~exist('spikePos','var')
                    spikePos = data.getSpikePositions(spikes,posAve);
                end
                instRate = analyses.instantRate(spikePos(:,1),posAve);
                kernel = (1 / helpers.sampleTimeFromData(posAve)) / 0.4;   % smoothing kernel = 0.4 sec
                scores = analyses.speedScore(Speed,instRate,kernel);
                speedScore = scores(2);
                clusterData(iCluster,iFolder,expNum).speed = speedScore;
            end
            
            %% theta
            if include.theta
                try
                    if length(spikes) > 100
                        [~,~,thetaIndSpikes] = thetaIndex(spikes);
                    else
                        thetaIndSpikes = nan;
                    end
                catch
                    thetaIndSpikes = nan;
                end
                try
                    thetaIndLFP = thetaIndexLFP(folders{1,iFolder},cellMatrix(iCluster,1));
                catch
                    thetaIndLFP = nan;
                end
                clusterData(iCluster,iFolder,expNum).thetaSpikes = thetaIndSpikes;
                clusterData(iCluster,iFolder,expNum).thetaLFP = thetaIndLFP;
            end
            if include.obj
                [objRate objTime] = objectAnalyis(map,objectLocations);
                clusterData(iCluster,iFolder,expNum).rateRatioO1 = objRate(1);
                clusterData(iCluster,iFolder,expNum).rateRatioO2 = objRate(2);
                clusterData(iCluster,iFolder,expNum).ratePvalO1 = objRate(3);
                clusterData(iCluster,iFolder,expNum).ratePvalO2 = objRate(4);
                clusterData(iCluster,iFolder,expNum).ratePvalAll = objRate(5);
                clusterData(iCluster,iFolder,expNum).timeRatioO1 = objTime(1);
                clusterData(iCluster,iFolder,expNum).timeRatioO2 = objTime(2);
                clusterData(iCluster,iFolder,expNum).timePvalO1 = objTime(3);
                clusterData(iCluster,iFolder,expNum).timePvalO2 = objTime(4);
                clusterData(iCluster,iFolder,expNum).timePvalAll = objTime(5);
            end
            
        end
    end
    
    %% store spatial correlation values at the end of each experiment
    if include.CC && (mod(iFolder,seshPerExp) == 0)
        for iCluster = 1:numClusters
            for iCorrs = 1:size(ccComps,1)
                
                sesh1comp = ccComps(iCorrs,1) + seshPerExp * (expNum-1);
                sesh2comp = ccComps(iCorrs,2) + seshPerExp * (expNum-1);
                CC = analyses.spatialCrossCorrelation(clusterData(iCluster,sesh1comp,expNum).rateMap,clusterData(iCluster,sesh2comp,expNum).rateMap);
                % store in repeating fashion for each session
                for iSession = (iFolder-seshPerExp+1):iFolder
                    eval(sprintf('clusterData(iCluster,iSession,expNum).cc%dvs%d = CC;',ccComps(iCorrs,1),ccComps(iCorrs,2)));
                end
                
            end
        end
    end
    
end

%% store everything in one cell array
emperor = createEmperorArray(clusterData,length(folders)/seshPerExp,include);

%% add headers and save excel sheet
emperorExcel = [colHeaders; emperor];
xlswrite(fullName,emperorExcel,'Main','A1');

%% add settings in another sheet
settingsNames = {'Cluster format', ...
    'Arena', ...
    'Map limits', ...
    '', ...
    'Spike width', ...
    'Spatial info, selectivity, sparsity', ...
    'Coherence', ...
    'Field info, border scores', ...
    'Grids', ...
    'HD', ...
    'Speed', ...
    'Theta', ...
    'Spatial correlations', ...
    'Objects', ...
    '', ...
    'Num sessions', ...
    '', ...
    'Smoothing', ...
    'Bin width (cm)', ...
    'Minimum occupancy', ...
    '', ...
    'Threshold for including surrounding bins (included if > thresh*peak)', ...
    'Spatial bin width (cm)', ...
    'Minimum bins for a field', ...
    'Minimum peak rate for a field (Hz?)', ...
    '', ...
    'Normalized threshold value used to search for peaks on the autocorrelogram (0:1)', ...
    '', ...
    'Full file path'};
if ~exist('seshPerExp','var')
    seshPerExp = '';
end
if ~exist('fieldThresh','var')
    fieldThresh = '';
end
if ~exist('minBins','var')
    minBins = '';
end
if ~exist('minPeak','var')
    minPeak = '';
end
if ~exist('gridThresh','var')
    gridThresh = '';
end

settingsValues = {clusterFormat, ...
    arena, ...
    num2str(mapLimits), ...
    '', ...
    include.spikeWidth, ...
    include.sss, ...
    include.coherence, ...
    include.fields, ...
    include.grid, ...
    include.HD, ...
    include.speed, ...
    include.theta, ...
    include.CC, ...
    include.obj, ...
    '', ...
    seshPerExp, ...
    '', ...
    smooth, ...
    binWidth, ...
    minTime, ...
    '', ...
    fieldThresh, ...
    binWidth, ...
    minBins, ...
    minPeak, ...
    '', ...
    gridThresh, ...
    '', ...
    fullName};
Settings = horzcat(settingsNames',settingsValues');
xlswrite(fullName,Settings,'Settings','A1');

toc

% load handel
% sound(y(1:7000),Fs)
