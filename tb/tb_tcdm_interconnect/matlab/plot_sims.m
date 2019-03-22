addpath('./matlab');

[stats] = read_stats('sim-results');
%%
plot_tests(stats);
%%