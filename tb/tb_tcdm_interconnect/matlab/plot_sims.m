%% setup paths
addpath(genpath('./matlab'));
mkdir plots

%% get simulation results
[stats] = read_stats('sim-results');

%% plot everything
plot_tests(stats);

export_fig 'sim-results/all' -png -pdf

%% plot only clos
plot_tests(stats, [], {'clos(m=0.5n)', 'clos(m=n)', 'clos(m=2n)'});

%% plot only banking factor 2
plot_tests(stats, {'8x16', '16x32', '32x64', '64x128', '128x256'});

export_fig 'sim-results/bf2' -png -pdf

%% plot subset of eval
%plot_tests(stats, {'8x8',     '8x16',  '8x32', ...
%                   '16x16',  '16x32',  '16x64', ...
%                   });
               
%export_fig 'sim-results/sel1' -png -pdf
               
%% for batch use
exit(0);