%% setup paths
addpath(genpath('./matlab'));
mkdir plots

%% get simulation results
[stats] = read_stats('sim-results');
%%
fairness_test(stats, 0.13);

%%
stats = read_synth('sim-results', stats);

%% clos networks
plot_tests(stats, {'8x16'}, {'clos_2mn', 'clos_m1n', 'clos_m2n','lic'});
% export_fig 'sim-results/clos' -png -pdf

%% selection
plot_tests(stats,  {'64x64','64x128','64x256'}, {'bfly2_n1', 'bfly2_n2','bfly2_n4','bfly4_n1', 'bfly4_n2','bfly4_n4', 'lic'});
% export_fig 'sim-results/selection' -png -pdf


%% plot only banking factor 2
plot_tests(stats, {'64x64','64x128','64x256'}, {'clos_2mn', 'clos_m1n', 'clos_m2n','lic'});

export_fig 'sim-results/bf2' -png -pdf

%% 8 masters
scatterplot_tests(stats, '8x', {'clos_2mn', 'clos_m1n', 'clos_m2n', 'bfly2_n1', 'bfly2_n2','bfly2_n4', 'bfly4_n1', 'bfly4_n2','bfly4_n4', 'lic'},'random uniform (p_{req}=1.00)');
% export_fig 'sim-results/pareto_8x' -png -pdf

%% 16 masters
% scatterplot_tests(stats, '16x', {'clos_2mn', 'clos_m1n', 'clos_m2n', 'bfly2_n1', 'bfly2_n2','bfly2_n4', 'bfly4_n1', 'bfly4_n2','bfly4_n4', 'lic'},'random uniform (p_{req}=1.00)');
scatterplot_tests(stats, '16x', {'clos_2mn', 'clos_m1n', 'clos_m2n', 'bfly2_n1', 'bfly2_n2','bfly2_n4', 'bfly4_n1', 'bfly4_n2','bfly4_n4', 'lic'},'random linear bursts (p_{req}=1.00, len_{max}=100.00)');
export_fig 'sim-results/pareto_16x' -png -pdf

%% 32 masters
% scatterplot_tests(stats, '32x', {'clos_2mn', 'clos_m1n', 'clos_m2n', 'bfly2_n1', 'bfly2_n2','bfly2_n4', 'bfly4_n1', 'bfly4_n2','bfly4_n4', 'lic'},'random uniform (p_{req}=1.00)');
scatterplot_tests(stats, '32x', {'clos_2mn', 'clos_m1n', 'clos_m2n', 'bfly2_n1', 'bfly2_n2','bfly2_n4', 'bfly4_n1', 'bfly4_n2','bfly4_n4', 'lic'},'random linear bursts (p_{req}=1.00, len_{max}=100.00)');
export_fig 'sim-results/pareto_32x' -png -pdf

%% 64 masters
% scatterplot_tests(stats, '64x', {'clos_2mn', 'clos_m1n', 'clos_m2n', 'bfly2_n1', 'bfly2_n2','bfly2_n4', 'bfly4_n1', 'bfly4_n2','bfly4_n4', 'lic'},'random uniform (p_{req}=1.00)');
scatterplot_tests(stats, '64x', {'clos_2mn', 'clos_m1n', 'clos_m2n', 'bfly2_n1', 'bfly2_n2','bfly2_n4', 'bfly4_n1', 'bfly4_n2','bfly4_n4', 'lic'},'random linear bursts (p_{req}=1.00, len_{max}=100.00)');
export_fig 'sim-results/pareto_64x' -png -pdf

%% 128 masters
% scatterplot_tests(stats, '128x', {'clos_2mn', 'clos_m1n', 'clos_m2n', 'bfly2_n1', 'bfly2_n2','bfly2_n4', 'bfly4_n1', 'bfly4_n2','bfly4_n4','bfly4_n8', 'lic'},'random uniform (p_{req}=1.00)');
scatterplot_tests(stats, '128x', {'clos_2mn', 'clos_m1n', 'clos_m2n', 'bfly2_n1', 'bfly2_n2','bfly2_n4', 'bfly4_n1', 'bfly4_n2','bfly4_n4','bfly4_n8', 'lic'},'random linear bursts (p_{req}=0.50, len_{max}=100.00)');
export_fig 'sim-results/pareto_128x' -png -pdf

%% 256 masters
% scatterplot_tests(stats, '256x', {'bfly2_n4', 'bfly4_n1', 'bfly4_n2','bfly4_n4','bfly4_n8', 'lic'},'random uniform (p_{req}=1.00)');
scatterplot_tests(stats, '256x', {'bfly2_n4', 'bfly4_n1', 'bfly4_n2','bfly4_n4','bfly4_n8', 'lic'},'random linear bursts (p_{req}=1.00, len_{max}=100.00)');
export_fig 'sim-results/pareto_256x' -png -pdf

%% renaming of existing files (if needed)

% statFiles = split(ls(['sim-results' filesep '*m0p5n*']));
% 
% for k=1:length(statFiles)
%     if length(statFiles{k})>0
% %         regexprep(statFiles{k},'m0p5n','2mn')
%         movefile(statFiles{k},regexprep(statFiles{k},'m0p5n','2mn'));
%     end
% end

%%
plot_scaling(stats, {'8x8','16x16','32x32','64x64','128x128'}, {})
%%
plot_scaling(stats, {'8x16','16x32','32x64','64x128','128x256'}, {})
%%
plot_scaling(stats, {'8x32','16x64','32x128','64x256','128x512'}, {})
%% for batch use
exit(0);