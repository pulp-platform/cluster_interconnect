k = 2.^linspace(2,10,11);
plot(k,k.^2,'r.--');          
hold on
plot(k,sqrt(32.*k.^3),'bx--');
plot(k,sqrt(8.*k.^3),'gs--');
plot(k,4.2*k.*log2(k),'co--');
grid on

legend('lic', 'closs m=2n', 'closs m=2', 'bfly','location','northwest')
