function [] = plot_scaling(stats, configLabels, netLabels)
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% global plot configs
    %%%%%%%%%%%%%%%%%%%%%%%%%%%

    close;
    figure;
    
    cols    = colormap('lines');
    markers = ['o','d','s','<','>','v','h','^','+','-','x','.'];
   
    %%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% preprocess args
    %%%%%%%%%%%%%%%%%%%%%%%%%%%    
    
    fprintf('\n');
    
    if ~isempty(netLabels)
        tmp = {};
        for k = 1:length(netLabels)
            if any(strcmp(netLabels{k},stats.netTypes))
                tmp = [tmp netLabels(k)];
            else
                warning('netType %s not found in batch results, skipping config...', netLabels{k});
            end    
        end
        netLabels = tmp;
    else
        netLabels    = stats.netTypes;
    end

    if isempty(configLabels)
        configLabels=stats.configLabels;
    end

    masterConfigs = [];
    bankFacts = [];
    for k=1:length(configLabels)
        tmp = sscanf(configLabels{k},'%dx%d');
        masterConfigs(k)=tmp(1);
        bankFacts(k)=tmp(2)/tmp(1);
%         for j=1:length(configLabels{k})
%             if configLabels{k}(j) == 'x'
%                 masterConfigs{k} = configLabels{k}(1:j-1);
%             end
%         end
    end
    
    masterConfigs = unique(masterConfigs);
    bankFacts  = unique(bankFacts);
    
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% gather results
    %%%%%%%%%%%%%%%%%%%%%%%%%%% 

    res=nan(length(netLabels),length(bankFacts),length(masterConfigs));
    for n=1:length(netLabels)
        for c=1:length(configLabels)
            tst2=strcmp(configLabels{c}, stats.configLabels);
            tst3=strcmp(netLabels{n}, stats.netTypes);
            
            idx2 = find(tst2,1);  
            idx3 = find(tst3,1);  
            
            tmp = sscanf(configLabels{c},'%dx%d');
            
            tst = masterConfigs == tmp(1);
            idx = find(tst,1);  
            tst4 = bankFacts == tmp(2)/tmp(1);
            idx4 = find(tst4,1);  
            
            res(n,idx4,idx) = stats.synthArea(idx3,idx2,1);
        end
    end
    
    labels   = {};
    
    for n=1:length(netLabels)
        for c=1:length(bankFacts)
            labels = [labels {[netLabels{n} '_bf' num2str(bankFacts(c))]}]; 
        end
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% grant prob vs synth area
    %%%%%%%%%%%%%%%%%%%%%%%%%%%   

    hold on;
    for k=1:size(res,1)
        for j=1:size(res,2)
            plot(masterConfigs,squeeze(res(k,j,:)),'--','marker',markers(j),'color',cols(k,:),'markerEdgeColor','k');
        end
    end
    box on;
    grid on;
    
    legend(labels,'interpreter','none');
    xticks(masterConfigs)
    set(gca,'yscale','log');
    set(gca,'xscale','log');
   
    title('scaling behavior');
    xlabel('master ports');
    ylabel('complexity [\mum^2]');
% 
%     %%%%%%%%%%%%%%%%%%%%%%%%%%%
%     %% grant prob vs synth area
%     %%%%%%%%%%%%%%%%%%%%%%%%%%%
%     
%     % plot the pareto line first
%     x=1-res(:,:,1);
%     y=res(:,:,3);
%     x=x(:);
%     y=y(:);
% 
%     [x,idx]=sortrows(x);
%     y=y(idx);
%     px = x(1);
%     py = y(1);
%     for k=2:length(x)
%         if y(k)<py(end)
%             px = [px;x(k);x(k)];
%             py = [py;py(end);y(k)];
%         end
%     end    
% 
%     axx(1)=0;
%     axx(2)=max(x)*1.1;
%     axx(3)=0;
%     axx(4)=max(y)*1.1;
%     px = [px(1);px;axx(2)];
%     py = [axx(4);py;py(end)];
%     plot(px,py,'color',[0.5 0.5 0.5]);
%     axis(axx);
% 
%     % plot the banking factor labels
%     hold on
%     sz = 35;
%     fzs = 9;
%     xoff=0.01;
%     yoff=0;
%     for k=1:size(res,2)
%         for j=1:size(res,1)
%             text(1-res(j,k,1)+xoff, res(j,k,3)+yoff, bankFacts{j}, 'FontSize', fzs);
%         end
%     end
%     
%     % plot the markers
%     for k=1:size(res,2)
%         h(k)=scatter(1-res(:,k,1), res(:,k,3), sz, 'filled', 'marker', markers(k),'MarkerEdgeColor','k','LineWidth',0.5);
%     end
%     
%     % further annotation
%     grid on
%     box on
%     ylabel('area [\mum^2]');
%     xlabel('1 - p_{gnt}');
% 
%     legend(h,netLabels,'location','northeast','interpreter','none');
%     title([masterConfig ' Master Ports']);

end