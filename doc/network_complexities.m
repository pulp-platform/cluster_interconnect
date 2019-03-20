figure
k = 2.^linspace(2,10,9);
loglog(k,k.^2*3303000/512^2,'r.--');          
hold on
loglog(k,sqrt(32.*k.^3)*3303000/512^2,'bx--');
loglog(k,sqrt(8.*k.^3)*3303000/512^2,'gs--');
loglog(k,k.*log2(k)*243500/512/log2(512),'co--');
grid on


legend('lic', 'closs M=2N', 'closs M=N', 'bfly','location','northwest')
xlabel('banks N');
ylabel('complexity [\mum^2]');