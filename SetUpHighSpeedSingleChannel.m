% SetUpHighSpeedSingleChannel.m - Ultra-fast single channel Doppler acquisition
% Optimized for maximum PRF with minimal data transfer and processing

clear all

%% Key Speed Optimization Parameters
% === SPEED OPTIMIZATION #1: Minimal depth range ===
P.startDepth = 5;    % Start close to transducer
P.endDepth = 50;     % Short acquisition depth (reduces acquisition time)

% === SPEED OPTIMIZATION #2: Single channel operation ===
P.numTx = 1;         % Single transmitter
P.numRx = 1;         % Single receiver
P.txElement = 64;    % Center element for transmit
P.rxElement = 64;    % Same element for receive

%% Define system parameters
Resource.Parameters.numTransmit = 128;  % System capability
Resource.Parameters.numRcvChannels = 128;
Resource.Parameters.speedOfSound = 1540;
Resource.Parameters.verbose = 2;
Resource.Parameters.simulateMode = 0;

% === SPEED OPTIMIZATION #3: Asynchronous acquisition ===
% Hardware runs independently from processing for maximum speed
Resource.Parameters.waitForProcessing = 0;  % Asynchronous mode

%% Specify Trans structure
Trans.name = 'L11-4v';  % Using standard linear array
Trans.units = 'wavelengths';
Trans = computeTrans(Trans);
Trans.maxHighVoltage = 50;

%% Define minimal PData for single point/line
% === SPEED OPTIMIZATION #4: Minimal reconstruction region ===
PData.PDelta = [1, 0, 0.5];  % Single lateral position
PData.Size(1) = ceil((P.endDepth-P.startDepth)/PData.PDelta(3));
PData.Size(2) = 1;  % Single column for one beam
PData.Size(3) = 1;
PData.Origin = [0, 0, P.startDepth];  % Centered on selected element

%% Specify Media (for simulation)
pt1;
Media.function = 'movePoints';

%% Specify Resources
% === SPEED OPTIMIZATION #5: Large multi-frame buffer ===
Resource.RcvBuffer(1).datatype = 'int16';
Resource.RcvBuffer(1).rowsPerFrame = 1024;  % Small for short depth
Resource.RcvBuffer(1).colsPerFrame = Resource.Parameters.numRcvChannels;
Resource.RcvBuffer(1).numFrames = 1000;     % Large buffer for continuous acquisition

% === SPEED OPTIMIZATION #6: No InterBuffer needed ===
% Skip IQ processing for maximum speed in basic Doppler
Resource.InterBuffer(1).numFrames = 10;     % Small buffer for Doppler processing
Resource.ImageBuffer(1).numFrames = 1;      % Single frame for display

% Minimal display window
Resource.DisplayWindow(1).Title = 'High Speed Single Channel Doppler';
Resource.DisplayWindow(1).pdelta = 0.5;
ScrnSize = get(0,'ScreenSize');
Resource.DisplayWindow(1).Position = [250,(ScrnSize(4)-300)/2, 300, 300];
Resource.DisplayWindow(1).ReferencePt = [0,0,P.startDepth];
Resource.DisplayWindow(1).numFrames = 1;
Resource.DisplayWindow(1).AxesUnits = 'wavelengths';

%% Specify TW structure
% === SPEED OPTIMIZATION #7: Short transmit burst ===
TW(1).type = 'parametric';
TW(1).Parameters = [Trans.frequency, 0.67, 2, 1];  % 1 cycle burst (minimal duration)

%% Specify TX structure
TX(1).waveform = 1;
TX(1).Origin = [0, 0, 0];
TX(1).focus = P.endDepth/2;  % Simple fixed focus
TX(1).Steer = [0, 0];

% === SPEED OPTIMIZATION #8: Single element aperture ===
TX(1).Apod = zeros(1, Trans.numelements);
TX(1).Apod(P.txElement) = 1;  % Only one transmitter active
TX(1).Delay = computeTXDelays(TX(1));

%% Specify TGC
TGC.CntrlPts = [0,141,275,404,510,603,702,782];
TGC.rangeMax = P.endDepth;
TGC.Waveform = computeTGCWaveform(TGC);

%% Specify Receive structures
% === SPEED OPTIMIZATION #9: Minimal receive aperture ===
% === SPEED OPTIMIZATION #10: Narrow bandwidth for Doppler ===
numAcqs = Resource.RcvBuffer(1).numFrames;
Receive = repmat(struct('Apod', zeros(1,Trans.numelements), ...
                       'startDepth', P.startDepth, ...
                       'endDepth', P.endDepth, ...
                       'TGC', 1, ...
                       'bufnum', 1, ...
                       'framenum', 1, ...
                       'acqNum', 1, ...
                       'sampleMode', 'BS50BW', ... % Narrow bandwidth for Doppler
                       'mode', 0, ...
                       'callMediaFunc', 1), 1, numAcqs);

% Configure each receive - only one channel active
for i = 1:numAcqs
    Receive(i).Apod(P.rxElement) = 1;  % Single receive element
    Receive(i).framenum = i;
end

%% Specify Recon structure
Recon = struct('senscutoff', 0.5, ...
               'pdatanum', 1, ...
               'rcvBufFrame', -1, ...  % Process most recent frame
               'IntBufDest', [1,1], ...
               'ImgBufDest', [1,-1], ...
               'RINums', 1);

ReconInfo = struct('mode', 'replaceIntensity', ...
                   'txnum', 1, ...
                   'rcvnum', 1, ...
                   'regionnum', 1);

%% Specify Process structure for Doppler
Process(1).classname = 'Image';
Process(1).method = 'imageDisplay';
Process(1).Parameters = {'imgbufnum',1,...
                        'framenum',-1,...
                        'pdatanum',1,...
                        'pgain',1.0,...
                        'reject',2,...
                        'persistMethod','simple',...
                        'persistLevel',20,...
                        'interpMethod','4pt',...
                        'grainRemoval','none',...
                        'processMethod','none',...
                        'averageMethod','none',...
                        'compressMethod','power',...
                        'compressFactor',40,...
                        'display',1,...
                        'displayWindow',1};

%% Specify SeqControl and Events
% === SPEED OPTIMIZATION #11: Minimal time between acquisitions ===
SeqControl(1).command = 'jump';
SeqControl(1).argument = 1;
SeqControl(2).command = 'timeToNextAcq';
SeqControl(2).argument = 100;  % 100 microseconds = 10 kHz PRF!
SeqControl(3).command = 'returnToMatlab';
nsc = 4;

% === SPEED OPTIMIZATION #12: Hardware sequencer runs continuously ===
n = 1;
% Acquisition loop - hardware runs this continuously
for i = 1:Resource.RcvBuffer(1).numFrames
    Event(n).info = 'Single channel acquisition';
    Event(n).tx = 1;
    Event(n).rcv = i;
    Event(n).recon = 0;
    Event(n).process = 0;
    Event(n).seqControl = [2, nsc];  % timeToNextAcq and transferToHost
    SeqControl(nsc).command = 'transferToHost';
    nsc = nsc + 1;
    n = n + 1;
    
    % === SPEED OPTIMIZATION #13: Separate processing events ===
    % Processing happens asynchronously when CPU is available
    if mod(i,100) == 0  % Process every 100th frame
        Event(n).info = 'Process and display';
        Event(n).tx = 0;
        Event(n).rcv = 0;
        Event(n).recon = 1;
        Event(n).process = 1;
        Event(n).seqControl = 0;
        n = n + 1;
    end
    
    % Return to Matlab periodically for GUI response
    if mod(i,200) == 0
        Event(n-1).seqControl = 3;  % returnToMatlab
    end
end

% Jump back to start
Event(n).info = 'Jump to start';
Event(n).tx = 0;
Event(n).rcv = 0;
Event(n).recon = 0;
Event(n).process = 0;
Event(n).seqControl = 1;

%% User Interface Controls
% PRF control slider
UI(1).Control = {'UserB2','Style','VsSlider',...
                 'Label','PRF (kHz)',...
                 'SliderMinMaxVal',[1,50,10],...
                 'SliderStep',[0.1,1],...
                 'ValueFormat','%3.1f'};
UI(1).Callback = text2cell('%PRFCallback');

% Save all structures to a .mat file
save('MatFiles/HighSpeedSingleChannel');
return

%% Callback functions
%PRFCallback
function PRFCallback(~,~,UIValue)
% Convert kHz to microseconds
timeToNext = round(1000/UIValue);
SeqControl(2).argument = timeToNext;
Control = evalin('base','Control');
Control.Command = 'update&Run';
Control.Parameters = {'SeqControl'};
assignin('base','Control',Control);
return
end
%PRFCallback
