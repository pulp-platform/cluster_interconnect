%% setup paths
addpath(genpath('./matlab'));
mkdir plots

%% get simulation results
[stats] = read_stats('sim-results');

fairness_test(stats, 0.15);

%% vanilla pbfly networks
configs = {};
n=1;
r=0;
configs=[configs {sprintf('pbfly2(n=%d,r=%d)',n,r)}];
configs=[configs {'lic'}];
plot_tests(stats,[], configs);
export_fig 'sim-results/pbfly2_vanilla' -png -pdf


%% pbfly networks, redundancy
configs = {};
n=1;
for r=[0,1,2]
    configs=[configs {sprintf('pbfly2(n=%d,r=%d)',n,r)}];
end
configs=[configs {'lic'}];
plot_tests(stats, {'16x16','16x32','16x64'}, configs);
export_fig 'sim-results/pbfly2_redundancy_16x' -png -pdf

%% pbfly networks, parallelism
configs = {};
r=0;
for n=[1,2,4]
    configs=[configs {sprintf('pbfly2(n=%d,r=%d)',n,r)}];
end
configs=[configs {'lic'}];
plot_tests(stats, {'16x16','16x32','16x64'}, configs);
export_fig 'sim-results/pbfly2_parallelism_16x' -png -pdf

%% clos networks
plot_tests(stats, [], {'clos(2m=n)', 'clos(m=n)', 'clos(m=2n)','lic'});
export_fig 'sim-results/clos' -png -pdf

%% selection
plot_tests(stats, [], {'pbfly2(n=1,r=0)', 'pbfly2(n=2,r=0)', 'clos(m=n)', 'lic'});
export_fig 'sim-results/selection' -png -pdf


%% plot only banking factor 2
plot_tests(stats, {'8x16', '16x32', '32x64'}, {'bfly2(r=0)','bfly2(r=1)','bfly2(r=2)','clos(2m=n)', 'clos(m=n)', 'clos(m=2n)','lic'});
% plot_tests(stats, {'8x16', '16x32', '32x64', '64x128', '128x256'}, {'bfly','clos(2m=n)', 'clos(m=n)', 'clos(m=2n)','lic'});

export_fig 'sim-results/bf2' -png -pdf

               
%% for batch use
exit(0);