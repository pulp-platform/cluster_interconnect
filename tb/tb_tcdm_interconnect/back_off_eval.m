function [cycle] = back_off_eval(nCores, maxBackoff, verbose)

% nCores = 32;
% maxBackoff = 0;

lr       = false(nCores,1);
sc       = false(nCores,1);
rand_cnt = zeros(nCores,1);
back_off = zeros(nCores,1);
fails    = zeros(nCores,1);

if verbose
    fprintf('\n\n----------------------------\n');
    fprintf('nCores = %d LR/SC sequence\n', nCores);
    fprintf('----------------------------\n');
end

cycle=1;
mem = nan;
while any(~ (lr & sc))

    if verbose
        fprintf('lr: [ ');
        fprintf('%d ',lr);
        fprintf(' ]\n');
        fprintf('sc: [ ');
        fprintf('%d ',sc);
        fprintf(' ]\n');
        fprintf('fails: [ ');
        fprintf('%d ',fails);
        fprintf(' ]\n');
        fprintf('cnt: [ ');
        fprintf('%d ',rand_cnt);
        fprintf(' ]\n');
        fprintf('backoff: [ ');
        fprintf('%d ',back_off);
        fprintf(' ]\n');
        fprintf('old reservation: %d\n',mem);
    end
    
    % decrement non-zero counters
    rand_cnt = rand_cnt - (rand_cnt>0);
    back_off = back_off - (back_off>0);
    
    % cores trying to reserve in this cycle
    res_lr = [];
    res_sc = [];
    
    for n=1:nCores
        % do sc
        if lr(n) && ~sc(n) && back_off(n)==0 && rand_cnt(n)==0
            res_sc = [res_sc n];
        % do lr
        elseif (~lr(n)) 
            res_lr = [res_lr n];
            lr(n) = true;
            % lr can take up to 16 cycles
            rand_cnt(n) = 16;
        end    
    end
    
    idx = [];
    if ~isempty(res_sc)
        % if there are multiple competing sc, draw one at random
        idx = res_sc(randi(length(res_sc)));
        sc(res_sc) = false;
        lr(res_sc) = false;
        if maxBackoff>0
            for k = 1:length(res_sc)
                fails(res_sc(k))    = min(fails(res_sc(k))+1,maxBackoff);
                back_off(res_sc(k)) = randi(2.^fails(res_sc(k)));
            end
        end
        
        if idx == mem
            lr(idx) = true; 
            sc(idx) = true; 
            fails(idx)    = 0;
            back_off(idx) = 0;
        end    
    end
    
    if ~isempty(res_lr)
        % if there are multiple competing lr, draw one at random
        mem = res_lr(randi(length(res_lr)));
    end
    
    if verbose
        fprintf('lr cands: [ ');
        fprintf('%d',res_sc);
        fprintf(' ]\n');
        fprintf('sc cands: [ ');
        fprintf('%d',res_lr);
        fprintf(' ]\n');
        fprintf('sc winner: %d\n',idx);
        fprintf('new reservation: %d\n',mem);
        fprintf('----------------------------\n');
    end
    
    cycle=cycle+1;
end

if verbose
    fprintf('\n\nnCores = %d, Resolution Cycles = %d\n', nCores, cycle);
end
end