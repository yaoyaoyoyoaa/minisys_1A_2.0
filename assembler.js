/* assembler.js - Fixed Imports */
(function() {
    window.MiniSys = window.MiniSys || {};
    const Utils = window.MiniSys.Utils;
    
    // [关键修复] 确保引用正确的指令集名称
    const InsList = window.MiniSys.Instructions || window.MiniSys.MinisysInstructions;
    if (!InsList) console.error("Instruction set not found! Check instruction.js");

    // [关键修复] 安全访问 Macro
    const MacroRules = (window.MiniSys.Macro && window.MiniSys.Macro.expansionRules) ? window.MiniSys.Macro.expansionRules : {};

    class TextSeg {
        constructor(startAddr, ins, labels) {
            this.startAddr = startAddr;
            this.ins = ins; 
            this.labels = labels;
        }
    }

    class DataSeg {
        constructor(startAddr, vars) {
            this.startAddr = startAddr;
            this.vars = vars;
        }
    }

    function expandMacros(asmLines) {
        let newAsm = [];
        for(let line of asmLines) {
            line = line.trim();
            if(!line || line.startsWith('#')) continue;
            
            let labelPrefix = "";
            let content = line;
            if (line.includes(':')) {
                let parts = line.split(':');
                labelPrefix = parts[0] + ": ";
                content = parts[1].trim();
            }
            
            if(!content) { newAsm.push(line); continue; }

            let matched = false;
            for (let ruleKey in MacroRules) {
                let rule = MacroRules[ruleKey];
                if (rule.pattern.test(content)) {
                    rule.pattern.test(content); // reset regex
                    let expanded = rule.replacer();
                    if (labelPrefix) expanded[0] = labelPrefix + expanded[0];
                    expanded.forEach(l => newAsm.push(l));
                    matched = true;
                    break;
                }
            }
            if(!matched) newAsm.push(line);
        }
        return newAsm;
    }

    function parseTextSeg(lines, startAddr) {
        let pc = startAddr;
        let labels = [];
        let instructions = []; 
        
        for(let line of lines) {
            if (line.match(/^\w+:/)) {
                let labelName = line.split(':')[0].trim();
                if (labels.find(l => l.name === labelName)) throw new Utils.SeuError(`重复标签: ${labelName}`);
                labels.push({ name: labelName, addr: pc });
                line = line.split(':')[1].trim();
            }
            if (!line) continue;

            let matchedDef = null;
            // InsList 可能未定义，如果 instruction.js 加载失败
            if (InsList) {
                for (let insDef of InsList) {
                    if (insDef.insPattern.test(line)) {
                        matchedDef = insDef;
                        break;
                    }
                }
            }
            if (!matchedDef) throw new Utils.SeuError(`未知指令: ${line}`);
            
            instructions.push({ asm: line, pc: pc, def: matchedDef });
            pc += 4;
        }

        let finalIns = instructions.map(item => {
            item.def.insPattern.test(item.asm);
            let binaryParts = item.def.components.map(comp => {
                if (typeof comp.toBinary === 'function') {
                    let res = comp.toBinary(); 
                    if (typeof res === 'object' && res.isLabel) {
                        let target = labels.find(l => l.name === res.name);
                        if (!target) throw new Utils.SeuError(`未定义标签: ${res.name}`);
                        
                        let val = 0;
                        if (res.offset) { 
                            val = (target.addr - (item.pc + 4)) / 4;
                        } else { 
                            val = target.addr / 4;
                        }
                        return Utils.decToBin(val, res.len);
                    }
                    return res;
                }
                return comp.val; 
            });
            let binStr = "";
            binaryParts.forEach(b => binStr += b);
            return binStr;
        });

        return {
            ins: finalIns, 
            startAddr: startAddr
        };
    }

    function assemble(source) {
        let lines = source.split(/\n/)
            .map(l => l.split('#')[0].split('//')[0].trim()) 
            .filter(l => l); 
            
        lines = expandMacros(lines);

        let dataLines = [];
        let textLines = [];
        let isText = true; 
        let textStart = 0x00000000;

        for (let l of lines) {
            if (l.toLowerCase().startsWith('.data')) { isText = false; continue; }
            if (l.toLowerCase().startsWith('.text')) { 
                isText = true; 
                let match = l.match(/\.text\s+(0x[\da-f]+|\d+)/i);
                if (match) textStart = parseInt(match[1]);
                continue; 
            }
            
            if (isText) textLines.push(l);
            else dataLines.push(l);
        }

        let textSeg = parseTextSeg(textLines, textStart);
        return { textSeg, dataSeg: null };
    }

    window.MiniSys.Assembler = {
        assemble: assemble,
        expandMacros: expandMacros
    };
})();