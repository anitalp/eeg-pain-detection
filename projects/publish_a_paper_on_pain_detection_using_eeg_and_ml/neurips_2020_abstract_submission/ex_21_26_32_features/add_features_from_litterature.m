%% Yacine Mahdid May 24 
% This script is addressing this task: 
% https://github.com/BIAPT/eeg-pain-detection/issues/21
% https://github.com/BIAPT/eeg-pain-detection/issues/26
% https://github.com/BIAPT/eeg-pain-detection/issues/32
%
% We basically needs to calculate Power, wPLI and peak frequency
% the first two need to be calculated at delta, theta, alpha, beta

%% Experiment Variable
% Path 
IN_DIR = "/media/yacine/Data/pain_and_eeg/all_data/";
FULL_HEADSET_LOCATION = "/home/yacine/Documents/BIAPT/eeg-pain-detection/projects/.data/full_headset_location.mat";
OUT_FILE = "/media/yacine/Data/pain_and_eeg/machine_learning_data/features_litterature.csv";

% Global Experiment Variable
rejected_participants = {
    'HE014','HE007', 'ME019', ...
    'ME034','ME040','ME042', 'ME046', 'ME048', 'ME050', 'ME052', 'ME053', ...
    'ME056', 'ME059', 'ME065'
    };

header = ["id", "type", "is_hot"];

bandpass_names = {'delta','theta', 'alpha', 'beta'};
bandpass_freqs = {[0.5 4], [4 8], [8 14], [14 32]};

% This will be the same throughout the features
WIN_SIZE = 10;
STEP_SIZE = 10;

data = load(FULL_HEADSET_LOCATION);
max_location = data.max_location;

%% Create data set
% Overwrite the file
delete(OUT_FILE);

% Write header to the features file
file_id = fopen(OUT_FILE,'w');
for i = 1:length(header)
    fprintf(file_id,'%s,', header(i));
end

% Write the rest of the header for the channel-wise power
for b_i = 1:length(bandpass_names)
    bandpass_name = bandpass_names{b_i};
    
    for c = 1:length(max_location)
        channel_label = max_location(c).labels;
        feature_label = sprintf("%s_%s_power",channel_label, bandpass_name);
        fprintf(file_id,'%s,', lower(feature_label)); 
    end    
end


fprintf(file_id,"\n");
fclose(file_id);

%% Iterating over all the participants

directories = dir(IN_DIR);

% Iterate over all directory since the first two are the '.' and '..' then
% we start at index 3
for id = 3:length(directories)
    folder = directories(id);
    disp(folder.name);
        
    % We skip participants that are problematic
    if(ismember(folder.name, rejected_participants))
        continue 
    end
    
    % participant variable init
    p_id = str2num(extractAfter(folder.name,"E"));
    is_healthy = contains(folder.name, 'HE');
    participant_path = strcat(folder.folder,filesep,folder.name);
    
    baseline_name = sprintf('%s_nopain.set',folder.name);
    hot_pain_name = sprintf('%s_hot1.set',folder.name);
    
    % load baseline recording, if nopain doesn't exist  will load rest
    % instead
    try
        baseline_recording = load_set(baseline_name, participant_path);
    catch
        baseline_name = sprintf('%s_rest.set',folder.name);
        baseline_recording = load_set(baseline_name, participant_path);
    end
    
    
    % If there is a problem here it means that there is a datapoint missing
    % Most problematic participant have been added to the rejected
    % participants list
    try
        hot_pain_recording = load_set(hot_pain_name, participant_path);
    catch
        printf("Should remove participant %s", hot_pain_name);
        return;
    end    

    %% Calculate Features
    recordings = { baseline_recording, hot_pain_recording };
    labels = {0, 1};
    for l_i = 1:length(recordings)
        recording = recordings{l_i};
        label = labels{l_i};
        
        features = [];
        for b_i = 1:length(bandpass_freqs)
            bandpass = bandpass_freqs{b_i};
            name = bandpass_names{b_i};
            fprintf("Calculating Feature at %s\n",name);

            [pad_powers] = calculate_power(recording, WIN_SIZE, STEP_SIZE, bandpass, max_location);
            features = horzcat(features, pad_powers);
        end
        
         %% Write the features to file
        [num_window, ~] = size(features);
        for w = 1:num_window
            row = features(w,:);
            dlmwrite(OUT_FILE, [p_id, is_healthy, label, row], '-append');
        end
        
    end
    
    
    %{

    
    power_distribution_baseline = na_topographic_distribution(baseline_recording, ...
        td.window_size, td.step_size, td.bandpass);
    
    baseline_location = power_distribution_baseline.metadata.channels_location;
    baseline_power = power_distribution_baseline.data.power;
    
    
    power_distribution_hot = na_topographic_distribution(hot_pain_recording, ...
        td.window_size, td.step_size, td.bandpass);
    
    hot_location = power_distribution_hot.metadata.channels_location;
    hot_power = power_distribution_hot.data.power;
    
    % If we want to add more feature put them over here %
    
    %% Write the features to file
    [num_window, ~] = size(baseline_power);
    for w_i = 1:num_window
        p_power = pad_result(baseline_power(w_i,:), baseline_location, max_location);
        dlmwrite(OUT_FILE, [p_id, is_healthy, 0, p_power], '-append');
    end
   
    [num_window, ~] = size(hot_power);
    for w_i = 1:num_window
        p_power = pad_result(hot_power(w_i,:), hot_location, max_location);        
        dlmwrite(OUT_FILE, [p_id, is_healthy, 1, p_power], '-append');     
    end
    %}
    
  
end

function [pad_powers] = calculate_power(recording, win_size, step_size, bandpass, max_location)
    power_struct = na_topographic_distribution(recording, win_size, step_size, bandpass);
    location = power_struct.metadata.channels_location;
    powers = power_struct.data.power;
    
    [num_window, ~] = size(powers);
    pad_powers = zeros(num_window,length(max_location));
    for w = 1:num_window
        pad_powers(w,:) = pad_result(powers(w,:), location, max_location);
    end
end

function [p_power] = pad_result(power, location, max_location)
% PAD_RESULT : will pad the result with the channels it has missing
% This is used to have a normalized power that has the same number of
% channels for all values. Will put NaN where a channel is missing.
    p_power = zeros(1, length(max_location));
    for l = 1:length(max_location)
        label = max_location(l).labels;
        
        % The channel may not be in the same order as location
        index = get_label_index(label, location);
        
        if (index == 0)
            p_power(l) = NaN; 
        else
            p_power(l) = power(index);
        end
   end
end

% Function to check if a label is present in a given location
function [label_index] = get_label_index(label, location)
    label_index = 0;
    for i = 1:length(location)
       if(strcmp(label,location(i).labels))
          label_index = i;
          return
       end
    end
end