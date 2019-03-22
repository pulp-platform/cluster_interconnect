function [] = plot_tests(stats, configFilter)

    if nargin < 2
        configFilter = [];
    end

    skip = 0.5;

    cols=colormap('lines');
    close;
    
    figure;
    totalRes = [];
    totalX   = [];
    labels   = {};
    tests    = {};
    pReq     = [];
    pReqPos  = [];
    for k=1:stats.numTestNamesFull
        res=[];
        for c=1:stats.numConfigs
            for n=1:stats.numNetTypes
                if any(configFilter) 
                    if ~strcmp(stats.configLabels{c}, configFilter)
                        continue;
                    end
                end
                
                tst = strcmp(stats.testNamesFull{k}, stats.testNameFull)   & ...
                      strcmp(stats.configLabels{c}, stats.configs)         & ...
                      strcmp(stats.netTypes{n}, stats.network)             ;
                    
                if sum(tst)>2
                    error('selection not unique');
                end
                
                idx = find(tst,1);  
                res(c,n,1) = mean(stats.ports{idx}(:,3));
                res(c,n,2) = mean(stats.ports{idx}(:,4));
            end
            tests  = [tests stats.testName{idx}];
            labels = [labels stats.configLabels{c}]; 
        end
        totalRes = cat(1, totalRes, res);
        x = (1:stats.numConfigs)+(k-1)*(stats.numConfigs+skip);
        totalX = [totalX x];
        pReq     = [pReq  stats.pReq(idx)];
        pReqPos  = [pReqPos mean(x)];
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% grant probability
    %%%%%%%%%%%%%%%%%%%%%%%%%%%
    yMax = 1.1;
    subplot(2,1,1);
    hold on;
    
    altGrey = [0.6, 0.8];
    % print test base name
    for t=1:stats.numTestNames
        tst=strcmp(stats.testNames{t},tests);
        idx=find(tst);
        
        fill([totalX(idx(1)),totalX(idx(end)),totalX(idx(end)),totalX(idx(1))] + [-(1+skip)/2,(1+skip)/2,(1+skip)/2,-(1+skip)/2], ...
             [0,0,yMax,yMax],[1 1 1] .* altGrey(mod(t-1,2)+1),'EdgeColor',[1 1 1] .* altGrey(mod(t-1,2)+1)); 
        
        text(mean(totalX(tst)),yMax-0.025,stats.testNames{t},'FontSize',9,'HorizontalAlignment','Center','FontWeight','bold');
    end
    grid on;
    box on;
    
    % plot black lines
    ax=axis();
    ax(1) = totalX(1)-1;
    ax(2) = totalX(end)+1;
    ax(3) = 0;
    ax(4) = yMax;
    axis(ax);
    for k=0:0.2:1
        plot(ax(1:2),[1 1].*k,':k');
    end
    plot(ax(1:2),[1 1],'k');
    
    % print request probs
    for k=1:length(pReq)
        text(mean(pReqPos(k)),yMax-0.075,sprintf('p=%.2f',pReq(k)),'FontSize',8,'HorizontalAlignment','Center');
    end    
    
    % bar plot
    b=bar(totalX, totalRes(:,:,1));
    for l=1:length(b)
        b(l).DisplayName = stats.netTypes{l};
        for j=1:size(b(l).CData,1)
            b(l).FaceColor = 'flat';
            b(l).LineStyle = 'none';
            b(l).CData(j,:) = cols(mod(l-1,stats.numNetTypes)+1,:);
        end
    end
    
    ylabel('p');
    title('average grant probability');
    xticks(totalX);
    xticklabels(labels);
    xtickangle(45);
    legend(b,'location','southeast');
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% avg wait cycles
    %%%%%%%%%%%%%%%%%%%%%%%%%%%
    yMax = 2;
    subplot(2,1,2);
    hold on;
    
    altGrey = [0.6, 0.8];
    % print test base name
    for t=1:stats.numTestNames
        tst=strcmp(stats.testNames{t},tests);
        idx=find(tst);
        
        fill([totalX(idx(1)),totalX(idx(end)),totalX(idx(end)),totalX(idx(1))] + [-(1+skip)/2,(1+skip)/2,(1+skip)/2,-(1+skip)/2], ...
             [eps,eps,yMax,yMax],[1 1 1] .* altGrey(mod(t-1,2)+1),'EdgeColor',[1 1 1] .* altGrey(mod(t-1,2)+1)); 
        
        text(mean(totalX(tst)),yMax*0.8,stats.testNames{t},'FontSize',9,'HorizontalAlignment','Center','FontWeight','bold');
    end
    grid on;
    box on;
    
    % plot black lines
    ax=axis();
    ax(1) = totalX(1)-1;
    ax(2) = totalX(end)+1;
    ax(3) = 0.01;
    ax(4) = yMax;
    axis(ax);
    for k=0:0.1:1
        plot(ax(1:2),[1 1].*k,':k');
    end
    for k=0:0.01:0.1
        plot(ax(1:2),[1 1].*k,':k');
    end
    plot(ax(1:2),[1 1],'k');
    
    % print request probs
    for k=1:length(pReq)
        text(mean(pReqPos(k)),yMax*0.6,sprintf('p=%.2f',pReq(k)),'FontSize',8,'HorizontalAlignment','Center');
    end    
    
    % bar plot
    b=bar(totalX, totalRes(:,:,2));
    for l=1:length(b)
        b(l).DisplayName = stats.netTypes{l};
        for j=1:size(b(l).CData,1)
            b(l).FaceColor = 'flat';
            b(l).LineStyle = 'none';
            b(l).CData(j,:) = cols(mod(l-1,stats.numNetTypes)+1,:);
        end
    end
    
    ylabel('cycles')
    title('average wait cycles');
    set(gca,'yscale','log')
    xticks(totalX);
    xticklabels(labels);
    xtickangle(45);
    legend(b,'location','southeast');
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% avg wait cycles
    %%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    set(gcf,'position',[200,300,100+1400,300+600]);
    
    
end