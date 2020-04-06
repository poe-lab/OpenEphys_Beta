function OpenEphysContinuousToNTT_03232017
%% Select Open Ephys continuous file to combine into .mat data set:
continFilename = strings(4,1);
for i = 1:4
    % Pick each CSC file that is part of the tetrode:
    [continFilename(i), continFilePath] = uigetfile({'*.continuous',...
        'Pick Open Ephys continuous file'},['Select CSC File #' num2str(i) ' of the Tetrode']);
end

%% Define the tetrode number to create:
tetrodeNum = [];
while isempty(tetrodeNum)
    prompt={'Select tetrode number:'};
    dlgTitle='Tetrode continous data file';
    lineNo=1;
    answer = inputdlg(prompt,dlgTitle,lineNo);
    tetrodeNum = str2double(answer{1,1});
    clear answer prompt dlgTitle lineNo
end

%% Define file names:
matFileName = ['OE_ContinTT' num2str(tetrodeNum) '.mat'];
matFile = fullfile(continFilePath, matFileName);
settingsFile = fullfile(continFilePath, 'settings.xml');
clear matFileName

%% Load OE data files and create .MAT data file:
tic
for i = 1:4
    continFile = fullfile(continFilePath, continFilename{i});
    if isequal(i,1)
        [data, timestamps, info] = load_open_ephys_data(continFile); %#ok<ASGLU>
        chNum = str2double(strrep(info.header.channel, 'CH', '')); %CSC channel number
        save(matFile,'tetrodeNum','chNum', 'data','timestamps','info','settingsFile','continFilename','continFilePath', '-v7.3')
        clear timestamps tetrodeNum
    else
        [data, ~, info] = load_open_ephys_data(continFile);
        chNum = str2double(strrep(info.header.channel, 'CH', '')); %CSC channel number
        m = matfile(matFile,'Writable',true);
        m.data(:,i) = data;
        m.chNum(1,i) = chNum;
    end
    clear data continFile info chNum
end
clear continFilePath continFilename
toc

%% Determine the # of 30 min bins to divide data into:
[dataLength,~] = size(m,'data');
load(matFile, 'info');
Fs = info.header.sampleRate;
binSize = 1800; % Bin size in seconds
num30minBins = ceil(dataLength/(Fs*binSize));
clear binSize

%% Process each bin of data:
deadTime = 250e-6;
maxlevel = 5;
peakLocs = 8;
waveLength = 32; 
% Create output variables:
spikeData = [];
spikeTs = [];

for i = 1:num30minBins
    startIdx = 1 + Fs*(i-1);
    if isequal(i, num30minBins)
        TetrodeData = m.data(startIdx:dataLength, 1:4);
        Timestamps = m.timestamps(startIdx:dataLength,1);
    else
        stopIdx = Fs * i;
        TetrodeData = m.data(startIdx:stopIdx, 1:4);
        Timestamps = m.timestamps(startIdx:stopIdx,1);
    end
    % Apply a broadband filter 
    FilteredData = wavefilter(TetrodeData', maxlevel);
    clear TetrodeData
    y_snle = snle(FilteredData, [1,1,1,1]);
    wireSigma= std(y_snle);
    minpeakh = wireSigma;
    clear wireSigma
    [spikeIdxAll, spikeTimesAll] = extractSpikeTimes(y_snle,minpeakh,Timestamps');
    clear Timestamps y_snle 

    [spikeTimesClear, spikeIdxClear] = clearDeadTime(spikeIdxAll,spikeTimesAll,deadTime);
    spikeTs = [spikeTs; spikeTimesClear];
    clear spikeTimesClear
    waveforms = extractWaveforms(FilteredData, spikeIdxClear, peakLocs, waveLength);
    spikeData = [spikeData; waveforms];
    clear waveforms
end

%% The sections commented out below are needed if exact AD channels are wanted.
% %% Load channel map from OE settings file:
% % Initialize variables.
% delimiter = '';
% startRow = 6;
% 
% % Format for each line of text:
% formatSpec = '%q%[^\n\r]'; % Read in strings for each line in file.
% 
% % Open the text file.
% fileID = fopen(settingsFile,'r');
% 
% % Read columns of data according to the format.
% textscan(fileID, '%[^\n\r]', startRow-1, 'WhiteSpace', '', 'ReturnOnError', false, 'EndOfLine', '\r\n');
% dataArray = textscan(fileID, formatSpec, 'Delimiter', delimiter, 'MultipleDelimsAsOne', true, 'ReturnOnError', false);
% 
% % Close the text file.
% fclose(fileID);
% 
% % Allocate imported array to column variable names
% settings = dataArray{:, 1};
% 
% % Clear temporary variables
% clearvars settingsFile delimiter startRow formatSpec fileID dataArray ans;
% 
% %% Find AD channel number:
% % Need to create a FOR loop here if want to find each AD channel
% info = m.info;
% x = strmatch(['<CHANNEL name="' info.header.channel '" number='], settings);
% channelStr = settings{x};
% clear settings x
% channelStr = replace(channelStr,'<CHANNEL name="CH5" number="','');
% ADchannel = textscan(channelStr,'%f %*[^\n]'); %AD channel number starting at Ch 0
% clear channelStr

%% Get the variables Neuralynx NCS Header:
% Extract open date and time:
A = textscan(info.header.date_created,'%s %s');
openDate = datestr(A{1,1}, 23);
timeInSec = str2double(A{1,2})/info.header.sampleRate;
h = floor(timeInSec/3600); % find # of hours since start of recording
timeInSec = mod(timeInSec, 3600);
m = floor(timeInSec/60); % find # of minutes since start of recording
s = mod(timeInSec, 60); % find # of seconds since start of recording
dateVector = [2000, 1, 1, h, m, s];
openTime = datestr(dateVector, 'HH:MM:SS.FFF');
clear A timeInSec h m s dateVector

% Extract close date and time:
closeDate = openDate; % !!!Need to change this!!!
timeInSec = ceil(m.timestamps(dataLength,1));
h = floor(timeInSec/3600); % find # of hours since start of recording
timeInSec = mod(timeInSec, 3600);
m = floor(timeInSec/60); % find # of minutes since start of recording
s = mod(timeInSec, 60); % find # of seconds since start of recording
dateVector = [2000, 1, 1, h, m, s];
closeTime = datestr(dateVector, 'HH:MM:SS.FFF');
clear timeInSec h m s dateVector

%% Create the Neuralynx NTT Header:
% To solve for ADBitVolts:
%   (Input Range in microvolts)/(1000000 * ADMAxValue)
%   The 1000000 divisor is to convert from microvolts to volts.
%   ADMaxValue = 32767;
nttFile = strrep(matFile, '.mat', '.ntt');
chNum = m.chNum - 1;
nttHeader = {'######## Neuralynx Data File Header ';
    ['## File Name ' nttFile];
    ['## Time Opened (m/d/y): ' openDate '  (h:m:s.ms) ' openTime];
    ['## Time Closed (m/d/y): ' closeDate '  (h:m:s.ms) ' closeTime];
    '-CheetahRev 5.5.1 ';'';
    ['-AcqEntName TT' num2str(tetrodeNum)]; %Shift TT # by +1 for Neuralynx
    '-FileType Spike';
    '-RecordSize 304'; %!!!Not sure about this
    '';'-HardwareSubSystemName AcqSystem1';
    '-HardwareSubSystemType DigitalLynx';
    ['-SamplingFrequency ' num2str(info.header.sampleRate)];
    '-ADMaxValue 32767'; %!!!Not sure about this
    '-ADBitVolts 7.62963e-009 7.62963e-009 7.62963e-009 7.62963e-009 '; %!!!Not sure about this
    '';
    '-NumADChannels 4';
    ['-ADChannel ' num2str(chNum(1)) ' ' num2str(chNum(2)) ' ' num2str(chNum(3)) ' ' num2str(chNum(4)) ' '];
    '-InputRange 250 250 250 250 '; %!!!Not sure about this
    '-InputInverted False';
    '-DSPLowCutFilterEnabled True'; 
    '-DspLowCutFrequency 300'; 
    '-DspLowCutNumTaps 64'; %!!!Not sure about this
    '-DspLowCutFilterType FIR';
    '-DSPHighCutFilterEnabled True'; %!!!Not sure about this
    '-DspHighCutFrequency 6000'; 
    '-DspHighCutNumTaps 32'; %!!!Not sure about this
    '-DspHighCutFilterType FIR';
    '-DspDelayCompensation Disabled'; %!!!Not sure about this
    '-DspFilterDelay_µs 0'; %!!!Not sure about this
    ['-WaveformLength ' num2str(size(spikeData,2))];
    '-AlignmentPt 8'; %!!!Not sure about this
    ['-ThreshVal ' num2str(info.thresh(1)) ' ' num2str(info.thresh(1)) ' ' num2str(info.thresh(1)) ' ' num2str(info.thresh(1)) ' '];
    '-MinRetriggerSamples 9'; %!!!Not sure about this
    '-SpikeRetriggerTime 250'; %!!!Not sure about this
    '-DualThresholding False';
    '';
    '-Feature Peak 0 0 ';
    '-Feature Peak 1 1 ';
    '-Feature Peak 2 2 ';
    '-Feature Peak 3 3 ';
    '-Feature Valley 4 0 ';
    '-Feature Valley 5 1 ';
    '-Feature Valley 6 2 ';
    '-Feature Valley 7 3 ';};

%% Reshape waveform data:
spikeData = permute(spikeData,[2 3 1]);

%% Convert data from microvolts to AD Value:
spikeData = spikeData/(7.62963e-009 * 1000000);

%% Convert time stamps from seconds to microseconds:
spikeTs = spikeTs * 1000000;

%% Create Features variable:
X = min(spikeData, [],1);
X = squeeze(X);
Y= max(spikeData,[],1);
Y = squeeze(Y);
Q = [Y;X];
Features = Q;
clear X Y Q
ScNumbers = tetrodeNum * ones(1, length(spikeTs));
cellNumbers = zeros(1, length(spikeTs));
Mat2NlxSpike(nttFile, 0, 1, [], [1 1 1 1 1 1], spikeTs',...
    ScNumbers, cellNumbers, Features, spikeData, nttHeader);