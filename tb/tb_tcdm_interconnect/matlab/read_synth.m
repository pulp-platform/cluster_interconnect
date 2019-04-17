function [stats] = read_synth(directory, stats)
% this function reads synthesis results and annotates the stats struct
% configurations with no synthesis result will be set to nan
    
    fprintf('\nreading synthesis results...\n');
    
    stats.synthArea = nan(length(stats.netTypes), length(stats.configLabels), 3);
    numFiles = 0;
    numSkipped = 0;
    for k = 1:length(stats.netTypes)
        for j = 1:length(stats.configLabels)
            fileName = [directory filesep stats.netTypes{k} '_' stats.configLabels{j} '_area.rpt'];
            
            if exist(fileName, 'file')
                [~,out] = system(['grep "Total cell area:" ' fileName ' | awk -e ''{print $4;}'' ']);
                stats.synthArea(k,j,1) = sscanf(out,'%f',1);
                [~,out] = system(['grep "Combinational area:" ' fileName ' | awk -e ''{print $3;}'' ']);
                stats.synthArea(k,j,2) = sscanf(out,'%f',1);
                [~,out] = system(['grep "Noncombinational area:" ' fileName ' | awk -e ''{print $3;}'' ']);
                stats.synthArea(k,j,3) = sscanf(out,'%f',1);
                numFiles = numFiles + 1;
            else
                warning('No Synthesis results found for %s', [stats.netTypes{k} '_' stats.configLabels{j}]);
                numSkipped = numSkipped + 1;
            end 
        end
    end    
    
    fprintf('read %d synthesis results (%d skipped)\n\n', numFiles, numSkipped);
end