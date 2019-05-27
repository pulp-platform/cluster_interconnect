%% simulate
numIter = 1;
maxK = 8;
maxC = 3;
cycle = zeros(maxC+1,maxK+1);
for i = 1:numIter
    i
    for c = 0:maxC
        names1{c+1} = [num2str(2.^c), ' cores'];  
        for k = 0:maxK
            names2{k+1} = [num2str(2^k) ' cycles'];
            cycle(c+1,k+1) = cycle(c+1,k+1) + back_off_eval(2^c, k, 0);
        end
    end
end    
cycle = cycle / numIter;

%% plot
semilogy(2.^(0:maxK), cycle', '--d');
box on;
grid on;
legend(names1);
ylabel('cycles');
xlabel('max back off');

%% plot
figure
semilogy(2.^(0:maxC), cycle, '--d');
box on;
grid on;
legend(names2);
ylabel('cycles');
xlabel('#cores');