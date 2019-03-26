function [cost] = closCost(k, b, c)
    n    = 2.^ceil(log2(sqrt(k ./ (1+1./b))));
    m    = 2.^ceil(log2(c.*n));
    r    = 2.^ceil(log2(k./n));
    cost = r.*n./b.*m + m.*r.^2 + r.*m.*n;
    
    if length(k) == 1
        fprintf('\nClos cost: \nk=%d, b=%d, c=%d\nm=%d, n=%d, r=%d\n-> cost = %.2f\n\n', k, b, c, m, n, r, cost);
    end    
end