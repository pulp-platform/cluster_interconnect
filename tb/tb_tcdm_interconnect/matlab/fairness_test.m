function [idx] = fairness_test(stats, tol)
%fairness_test checks whether grant probability std deviation is within tolerance
    
    fprintf('\nFairness check with tol=%.2f\n\n', tol);
    failingTests = '';
    idx = [];
    for k = 1:length(stats.ports)
        tst_mean = mean(stats.ports{k}(:,2));
        tst_std  = std(stats.ports{k}(:,2));
        str  = 'OK';
        str2 = '';
        if tst_std ./ tst_mean > tol 
            str = 'FAILED';
            str2 = [stats.network{k} ' ' stats.configs{k} ' ' stats.testNameFull{k}];
            failingTests = [failingTests str2 '\n'];
        end
        fprintf('> mean=%04.2f std=%04.2f -> %s %s\n', tst_mean, tst_std, str, str2);
        idx = [idx k];    
    end
    
    if ~isempty(str)
        fprintf(['\n\nSome tests have failed:\n', failingTests]);
    else
        fprintf('\n\nAll tests passed with tol=%.2f!\n', tol);
    end
end
