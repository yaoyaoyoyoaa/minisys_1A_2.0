/* macro.js - Compatibility Version */
(function() {
    window.MiniSys = window.MiniSys || {};

    const macroDefinitions = {
        expansionRules: {
            // Stack operations
            push: {
                pattern: /^push\s+(\$\w+)/i,
                replacer: () => ['addi $sp, $sp, -4', `sw ${RegExp.$1}, 0($sp)`]
            },
            pop: {
                pattern: /^pop\s+(\$\w+)/i,
                replacer: () => [`lw ${RegExp.$1}, 0($sp)`, 'addi $sp, $sp, 4']
            },
            // Move: move $t0, $t1 -> addu $t0, $0, $t1
            move: {
                pattern: /^move\s+(\$\w+),\s*(\$\w+)/i,
                replacer: () => [`addu ${RegExp.$1}, $0, ${RegExp.$2}`]
            },
            // Greater comparison jumps
            jg: {
                pattern: /^jg\s+(\$\w+),\s*(\$\w+),\s*(\w+)/i,
                replacer: () => [
                    'addi $sp, $sp, -4', 'sw $1, 0($sp)', 
                    `slt $1, ${RegExp.$2}, ${RegExp.$1}`, 
                    `bne $1, $0, ${RegExp.$3}`,
                    'lw $1, 0($sp)', 'addi $sp, $sp, 4'
                ]
            },
            // Load Immediate (Simple 16-bit)
            // 复杂的 li (32位) 会由 Assembler 内部处理或此处扩展
            li: {
                pattern: /^li\s+(\$\w+),\s*(-?0x[\da-f]+|-?\d+)/i,
                replacer: () => {
                    let imm = RegExp.$2;
                    let val = imm.startsWith('0x') ? parseInt(imm, 16) : parseInt(imm, 10);
                    // 如果是 16 位数，直接 addiu
                    if (val >= -32768 && val <= 32767) {
                        return [`addiu ${RegExp.$1}, $0, ${imm}`];
                    }
                    // 如果是 32 位数，拆分为 lui + ori
                    let upper = (val >>> 16) & 0xFFFF;
                    let lower = val & 0xFFFF;
                    return [`lui ${RegExp.$1}, 0x${upper.toString(16)}`, `ori ${RegExp.$1}, ${RegExp.$1}, 0x${lower.toString(16)}`];
                }
            }
        }
    };

    // [关键修复] 同时挂载到 Macro 和 Macros，兼容不同版本的 assembler.js
    window.MiniSys.Macro = macroDefinitions;
    window.MiniSys.Macros = macroDefinitions;
})();