/* register.js */
(function() {
    window.MiniSys = window.MiniSys || {};
    const Utils = window.MiniSys.Utils;

    const registerNames = [
        'zero', 'at', 'v0', 'v1', 'a0', 'a1', 'a2', 'a3',
        't0', 't1', 't2', 't3', 't4', 't5', 't6', 't7',
        's0', 's1', 's2', 's3', 's4', 's5', 's6', 's7',
        't8', 't9', 'k0', 'k1', 'gp', 'sp', 'fp', 'ra',
    ];

    window.MiniSys.Register = {
        regToBin: (reg) => {
            reg = reg.replace('$', '').trim();
            let regNumber;
            // 检查是否是数字
            if (reg.split('').every(c => '0123456789'.includes(c))) {
                regNumber = Number(reg);
            } else {
                regNumber = registerNames.indexOf(reg);
            }
            
            if (regNumber < 0 || regNumber > 31) {
                throw new Utils.SeuError(`错误的寄存器号：${reg}`);
            }
            return Utils.decToBin(regNumber, 5);
        }
    };
})();