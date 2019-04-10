% this generates the clos parameters, to be dumped into the SV wrapper
% m=2n
k=[2:12];

bankFacts = [0:4];
redFacts  = [0.5,1,2];
width     = 16;

fprintf('\n\n');
fprintf('// LUT params for Clos net with configs: ');
fprintf('%d: m=%.2f*n, ',[1:length(redFacts); redFacts]);
fprintf('\n// to be indexed with [config_idx][$clog2(BankingFact)][$clog2(NumBanks)]\n');
fprintf('// generated with MATLAB script gen_clos_params.m\n');
chars = ['N','M','R'];
for j = 1:3
    str = sprintf('localparam logic [%d:%d][%d:%d][%d:%d][%d:0] clos%s = {',length(redFacts),1,max(bankFacts),min(bankFacts),max(k),min(k),width-1,chars(j));
    fprintf(str);
    for c = fliplr(redFacts)
        for b = fliplr(2.^bankFacts)
            [~,n,m,r] = clos_cost(fliplr(2.^k), b, c);
            switch j
                case 1 
                    tmp=n; 
                case 2 
                    tmp=m; 
                case 3 
                    tmp=r; 
            end        
            if b == 2^bankFacts(1) && c == redFacts(1)
                fprintf('%d''d%d,',[repmat(width,[1 length(k)-1]); tmp(1:end-1)]);
                fprintf('%d''d%d',width,tmp(end));
                fprintf('};\n');
            else
                fprintf('%d''d%d,',[repmat(width,[1 length(k)]); tmp]);
                fprintf('\n');
                fprintf(repmat(' ',[1, length(str)]));
            end
        end
    end
end
