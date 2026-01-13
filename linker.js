/* linker.js - Robust Version */
(function() {
    window.MiniSys = window.MiniSys || {};
    
    // [关键修改] 不要在这里定义 const Assembler = ...
    // 改为在函数内部动态获取，防止加载顺序导致的 undefined

    function countIns(asmText) {
        if (!asmText) return 0;
        let lines = asmText.split('\n')
            .map(l => l.split('#')[0].trim())
            .filter(l => l && !l.startsWith('.'));
        
        // [关键修改] 运行时动态调用，确保 Assembler 已加载
        if (!window.MiniSys.Assembler || !window.MiniSys.Assembler.expandMacros) {
            throw new Error("Assembler 模块未正确加载，请检查 assembler.js");
        }
        
        let expanded = window.MiniSys.Assembler.expandMacros(lines);
        
        let count = 0;
        for (let l of expanded) {
            if (!l.match(/^\w+:$/)) count++;
        }
        return count;
    }

    function linkAll(biosASM, userASM, intEntryASM, intHandlerASM) {
        const BIOS_LIMIT = 320; 
        const USER_LIMIT = 5120;
        const INT_ENTRY_OFFSET = 15360; 
        
        let biosLen = countIns(biosASM);
        let userLen = countIns(userASM);
        
        if (biosLen > BIOS_LIMIT) throw new Error(`BIOS 代码过长: ${biosLen}`);
        if (userLen > USER_LIMIT) throw new Error(`用户代码过长: ${userLen}`);
        
        let biosPad = BIOS_LIMIT - biosLen;
        let userPad = USER_LIMIT - userLen;
        
        let currentTotal = BIOS_LIMIT + USER_LIMIT;
        let midPad = INT_ENTRY_OFFSET - currentTotal;
        
        if (midPad < 0) throw new Error("代码重叠：用户代码区侵入中断区");

        let full = ".text 0x00000000\n";
        full += biosASM + "\n";
        full += "nop\n".repeat(biosPad);
        full += userASM + "\n";
        full += "nop\n".repeat(userPad);
        full += "nop\n".repeat(midPad); 
        full += (intEntryASM || "") + "\n";
        
        return full;
    }

    window.MiniSys.Linker = { linkAll: linkAll };
})();