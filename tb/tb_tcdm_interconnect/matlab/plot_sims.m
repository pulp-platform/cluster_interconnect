%% setup paths
addpath(genpath('./matlab'));
mkdir plots

%% get simulation results
[stats] = read_stats('sim-results');

fairness_test(stats, 0.15);

%% pbfly networks, parallelism
configs = {};
r=0;
for n=[1,2,4]
    configs=[configs {sprintf('bfly2(n=%d)',n)}];
end
configs=[configs {'lic'}];
plot_tests(stats, {'16x16','16x32','16x64'}, configs);
export_fig 'sim-results/bfly2_parallelism_16x' -png -pdf

%% clos networks
plot_tests(stats, [], {'clos(2m=n)', 'clos(m=n)', 'clos(m=2n)','lic'});
export_fig 'sim-results/clos' -png -pdf

%% selection
plot_tests(stats, [], {'bfly2(n=1)', 'bfly2(n=2)', 'clos(m=n)', 'lic'});
export_fig 'sim-results/selection' -png -pdf


%% plot only banking factor 2
plot_tests(stats, {'8x16', '16x32', '32x64'}, {'bfly2','clos(2m=n)', 'clos(m=n)', 'clos(m=2n)','lic'});

export_fig 'sim-results/bf2' -png -pdf

               
%% for batch use
exit(0);