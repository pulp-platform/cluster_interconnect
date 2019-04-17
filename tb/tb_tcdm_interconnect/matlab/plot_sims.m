%% setup paths
addpath(genpath('./matlab'));
mkdir plots

%% get simulation results
[stats] = read_stats('sim-results');

fairness_test(stats, 0.15);

%%
stats = read_synth('sim-results', stats);

%% pbfly networks, parallelism
configs = {};
r=0;
for n=[1,2,4]
    configs=[configs {sprintf('bfly2_n%d',n)}];
end
configs=[configs {'lic'}];
plot_tests(stats, {'16x16','16x32','16x64'}, configs);
export_fig 'sim-results/bfly2_parallelism_16x' -png -pdf

%% clos networks
plot_tests(stats, [], {'clos_2mn', 'clos_mn', 'clos_m2n','lic'});
export_fig 'sim-results/clos' -png -pdf

%% selection
plot_tests(stats, [], {'bfly2_n1', 'bfly2_n2','bfly2_n4', 'lic'});
export_fig 'sim-results/selection' -png -pdf


%% plot only banking factor 2
plot_tests(stats, {'8x16', '16x32', '32x64'}, {'bfly2','clos_2mn', 'clos_m1n', 'clos_m2n','lic'});

export_fig 'sim-results/bf2' -png -pdf

%% 32
scatterplot_tests(stats, '16x', {'clos_m0p5n', 'clos_m1n', 'clos_m2n', 'bfly2_n1', 'bfly2_n2','bfly2_n4', 'lic'},'random uniform (p_{req}=1.00)');

%% renaming of existing files (if needed)

% statFiles = split(ls(['sim-results' filesep '*m0p5n*']));
% 
% for k=1:length(statFiles)
%     if length(statFiles{k})>0
% %         regexprep(statFiles{k},'m0p5n','2mn')
%         movefile(statFiles{k},regexprep(statFiles{k},'m0p5n','2mn'));
%     end
% end

%% for batch use
exit(0);