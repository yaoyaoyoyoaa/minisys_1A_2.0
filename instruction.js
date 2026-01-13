/* instruction.js - Robust Version */
(function() {
    window.MiniSys = window.MiniSys || {};
    const Utils = window.MiniSys.Utils;
    const Reg = window.MiniSys.Register;

    class Instruction {
        constructor(symbol, fmt, components) {
            this.symbol = symbol;
            this.insPattern = fmt;
            this.components = components; 
        }
    }

    let insList = [];
    const def = (sym, fmt, comps) => insList.push(new Instruction(sym, fmt, comps));

    // 辅助模板
    const R = (op, funct) => [
        {lBit:31, rBit:26, val:'000000'},
        {lBit:25, rBit:21, toBinary: () => Reg.regToBin(RegExp.$2)}, // rs
        {lBit:20, rBit:16, toBinary: () => Reg.regToBin(RegExp.$3)}, // rt
        {lBit:15, rBit:11, toBinary: () => Reg.regToBin(RegExp.$1)}, // rd
        {lBit:10, rBit:6,  val:'00000'},
        {lBit:5,  rBit:0,  val: Utils.decToBin(funct, 6)}
    ];
    
    const I = (opcode) => [
        {lBit:31, rBit:26, val: Utils.decToBin(opcode, 6)},
        {lBit:25, rBit:21, toBinary: () => Reg.regToBin(RegExp.$2)}, // rs
        {lBit:20, rBit:16, toBinary: () => Reg.regToBin(RegExp.$1)}, // rt
        {lBit:15, rBit:0,  toBinary: () => Utils.literalToBin(RegExp.$3, 16)} // imm
    ];

    // --- 核心指令 ---
    def('add',  /^add\s+(\$\w+),\s*(\$\w+),\s*(\$\w+)/i, R('add', 0x20));
    def('addu', /^addu\s+(\$\w+),\s*(\$\w+),\s*(\$\w+)/i, R('addu', 0x21));
    def('sub',  /^sub\s+(\$\w+),\s*(\$\w+),\s*(\$\w+)/i, R('sub', 0x22));
    def('subu', /^subu\s+(\$\w+),\s*(\$\w+),\s*(\$\w+)/i, R('subu', 0x23));
    def('and',  /^and\s+(\$\w+),\s*(\$\w+),\s*(\$\w+)/i, R('and', 0x24));
    def('or',   /^or\s+(\$\w+),\s*(\$\w+),\s*(\$\w+)/i,  R('or', 0x25));
    def('xor',  /^xor\s+(\$\w+),\s*(\$\w+),\s*(\$\w+)/i, R('xor', 0x26));
    def('nor',  /^nor\s+(\$\w+),\s*(\$\w+),\s*(\$\w+)/i, R('nor', 0x27));
    def('slt',  /^slt\s+(\$\w+),\s*(\$\w+),\s*(\$\w+)/i, R('slt', 0x2A));
    def('sltu', /^sltu\s+(\$\w+),\s*(\$\w+),\s*(\$\w+)/i, R('sltu', 0x2B));

    def('addi',  /^addi\s+(\$\w+),\s*(\$\w+),\s*(-?\d+|0x[\da-f]+)/i, I(0x08));
    def('addiu', /^addiu\s+(\$\w+),\s*(\$\w+),\s*(-?\d+|0x[\da-f]+)/i, I(0x09));
    def('andi',  /^andi\s+(\$\w+),\s*(\$\w+),\s*(\d+|0x[\da-f]+)/i,   I(0x0C));
    def('ori',   /^ori\s+(\$\w+),\s*(\$\w+),\s*(\d+|0x[\da-f]+)/i,    I(0x0D));
    def('xori',  /^xori\s+(\$\w+),\s*(\$\w+),\s*(\d+|0x[\da-f]+)/i,   I(0x0E));
    def('slti',  /^slti\s+(\$\w+),\s*(\$\w+),\s*(-?\d+|0x[\da-f]+)/i, I(0x0A));
    def('sltiu', /^sltiu\s+(\$\w+),\s*(\$\w+),\s*(-?\d+|0x[\da-f]+)/i, I(0x0B));
    
    // Load/Store
    def('lw', /^lw\s+(\$\w+),\s*(-?\d+|0x[\da-f]+)\((\$\w+)\)/i, [
        {lBit:31, rBit:26, val: '100011'}, 
        {lBit:25, rBit:21, toBinary: () => Reg.regToBin(RegExp.$3)}, // base
        {lBit:20, rBit:16, toBinary: () => Reg.regToBin(RegExp.$1)}, // rt
        {lBit:15, rBit:0,  toBinary: () => Utils.literalToBin(RegExp.$2, 16)} // offset
    ]);
    def('sw', /^sw\s+(\$\w+),\s*(-?\d+|0x[\da-f]+)\((\$\w+)\)/i, [
        {lBit:31, rBit:26, val: '101011'}, 
        {lBit:25, rBit:21, toBinary: () => Reg.regToBin(RegExp.$3)},
        {lBit:20, rBit:16, toBinary: () => Reg.regToBin(RegExp.$1)},
        {lBit:15, rBit:0,  toBinary: () => Utils.literalToBin(RegExp.$2, 16)}
    ]);
    def('lb', /^lb\s+(\$\w+),\s*(-?\d+|0x[\da-f]+)\((\$\w+)\)/i, [
        {lBit:31, rBit:26, val: '100000'}, 
        {lBit:25, rBit:21, toBinary: () => Reg.regToBin(RegExp.$3)},
        {lBit:20, rBit:16, toBinary: () => Reg.regToBin(RegExp.$1)},
        {lBit:15, rBit:0,  toBinary: () => Utils.literalToBin(RegExp.$2, 16)}
    ]);
    def('sb', /^sb\s+(\$\w+),\s*(-?\d+|0x[\da-f]+)\((\$\w+)\)/i, [
        {lBit:31, rBit:26, val: '101000'}, 
        {lBit:25, rBit:21, toBinary: () => Reg.regToBin(RegExp.$3)},
        {lBit:20, rBit:16, toBinary: () => Reg.regToBin(RegExp.$1)},
        {lBit:15, rBit:0,  toBinary: () => Utils.literalToBin(RegExp.$2, 16)}
    ]);

    // Branch/Jump
    def('beq', /^beq\s+(\$\w+),\s*(\$\w+),\s*(\w+)/i, [
        {lBit:31, rBit:26, val: '000100'},
        {lBit:25, rBit:21, toBinary: () => Reg.regToBin(RegExp.$1)},
        {lBit:20, rBit:16, toBinary: () => Reg.regToBin(RegExp.$2)},
        {lBit:15, rBit:0,  toBinary: () => Utils.labelToBin(RegExp.$3, 16, true)}
    ]);
    def('bne', /^bne\s+(\$\w+),\s*(\$\w+),\s*(\w+)/i, [
        {lBit:31, rBit:26, val: '000101'},
        {lBit:25, rBit:21, toBinary: () => Reg.regToBin(RegExp.$1)},
        {lBit:20, rBit:16, toBinary: () => Reg.regToBin(RegExp.$2)},
        {lBit:15, rBit:0,  toBinary: () => Utils.labelToBin(RegExp.$3, 16, true)}
    ]);
    def('j', /^j\s+(\w+)/i, [
        {lBit:31, rBit:26, val: '000010'},
        {lBit:25, rBit:0,  toBinary: () => Utils.labelToBin(RegExp.$1, 26, false)}
    ]);
    def('jal', /^jal\s+(\w+)/i, [
        {lBit:31, rBit:26, val: '000011'},
        {lBit:25, rBit:0,  toBinary: () => Utils.labelToBin(RegExp.$1, 26, false)}
    ]);
    def('jr', /^jr\s+(\$\w+)/i, [
        {lBit:31, rBit:26, val: '000000'},
        {lBit:25, rBit:21, toBinary: () => Reg.regToBin(RegExp.$1)},
        {lBit:20, rBit:0,  val: '000000000000000001000'}
    ]);

    // [关键修复] 直接支持 move 指令 (映射为 addu $d, $0, $s)
    // move $rt, $rs -> addu $rt, $0, $rs
    def('move', /^move\s+(\$\w+),\s*(\$\w+)/i, [
        {lBit:31, rBit:26, val: '000000'}, // Opcode
        {lBit:25, rBit:21, val: '00000'},  // rs = $0
        {lBit:20, rBit:16, toBinary: () => Reg.regToBin(RegExp.$2)}, // rt = Source
        {lBit:15, rBit:11, toBinary: () => Reg.regToBin(RegExp.$1)}, // rd = Dest
        {lBit:10, rBit:6,  val: '00000'},  // shamt
        {lBit:5,  rBit:0,  val: '100001'}  // funct = addu (0x21)
    ]);

    // 其他指令
    def('lui', /^lui\s+(\$\w+),\s*(-?0x[\da-f]+|-?\d+)/i, [
        {lBit:31, rBit:26, val: '001111'},
        {lBit:25, rBit:21, val: '00000'},
        {lBit:20, rBit:16, toBinary: () => Reg.regToBin(RegExp.$1)},
        {lBit:15, rBit:0,  toBinary: () => Utils.literalToBin(RegExp.$2, 16)}
    ]);
    def('sll', /^sll\s+(\$\w+),\s*(\$\w+),\s*(\d+|0x[\da-f]+)/i, [
        {lBit:31, rBit:26, val: '000000'},
        {lBit:25, rBit:21, val: '00000'},
        {lBit:20, rBit:16, toBinary: () => Reg.regToBin(RegExp.$2)},
        {lBit:15, rBit:11, toBinary: () => Reg.regToBin(RegExp.$1)},
        {lBit:10, rBit:6,  toBinary: () => Utils.literalToBin(RegExp.$3, 5)},
        {lBit:5,  rBit:0,  val: '000000'}
    ]);
    def('sllv', /^sllv\s+(\$\w+),\s*(\$\w+),\s*(\$\w+)/i, [
        {lBit:31, rBit:26, val: '000000'},
        {lBit:25, rBit:21, toBinary: () => Reg.regToBin(RegExp.$3)},
        {lBit:20, rBit:16, toBinary: () => Reg.regToBin(RegExp.$2)},
        {lBit:15, rBit:11, toBinary: () => Reg.regToBin(RegExp.$1)},
        {lBit:10, rBit:0,  val: '00000000100'}
    ]);
    def('srlv', /^srlv\s+(\$\w+),\s*(\$\w+),\s*(\$\w+)/i, [
        {lBit:31, rBit:26, val: '000000'},
        {lBit:25, rBit:21, toBinary: () => Reg.regToBin(RegExp.$3)},
        {lBit:20, rBit:16, toBinary: () => Reg.regToBin(RegExp.$2)},
        {lBit:15, rBit:11, toBinary: () => Reg.regToBin(RegExp.$1)},
        {lBit:10, rBit:0,  val: '00000000110'}
    ]);
    def('mult', /^mult\s+(\$\w+),\s*(\$\w+)/i, [
        {lBit:31, rBit:26, val: '000000'},
        {lBit:25, rBit:21, toBinary: () => Reg.regToBin(RegExp.$1)},
        {lBit:20, rBit:16, toBinary: () => Reg.regToBin(RegExp.$2)},
        {lBit:15, rBit:0,  val: '0000000000011000'}
    ]);
    def('div', /^div\s+(\$\w+),\s*(\$\w+)/i, [
        {lBit:31, rBit:26, val: '000000'},
        {lBit:25, rBit:21, toBinary: () => Reg.regToBin(RegExp.$1)},
        {lBit:20, rBit:16, toBinary: () => Reg.regToBin(RegExp.$2)},
        {lBit:15, rBit:0,  val: '0000000000011010'}
    ]);
    def('mflo', /^mflo\s+(\$\w+)/i, [
        {lBit:31, rBit:26, val: '000000'},
        {lBit:25, rBit:16, val: '0000000000'},
        {lBit:15, rBit:11, toBinary: () => Reg.regToBin(RegExp.$1)},
        {lBit:10, rBit:0,  val: '00000010010'}
    ]);
    def('mfhi', /^mfhi\s+(\$\w+)/i, [
        {lBit:31, rBit:26, val: '000000'},
        {lBit:25, rBit:16, val: '0000000000'},
        {lBit:15, rBit:11, toBinary: () => Reg.regToBin(RegExp.$1)},
        {lBit:10, rBit:0,  val: '00000010000'}
    ]);
    def('nop', /^nop/i, [{lBit:31, rBit:0, val: '0'.repeat(32)}]);

    def('mtc0', /^mtc0\s+(\$\w+),\s*(\d+)/i, [
        {lBit:31, rBit:26, val: '010000'},
        {lBit:25, rBit:21, val: '00100'}, 
        {lBit:20, rBit:16, toBinary: () => Reg.regToBin(RegExp.$1)},
        {lBit:15, rBit:11, toBinary: () => Utils.decToBin(parseInt(RegExp.$2), 5)},
        {lBit:10, rBit:0,  val: '00000000000'}
    ]);
    def('eret', /^eret/i, [{lBit:31, rBit:0, val: '01000010000000000000000000011000'}]);

    window.MiniSys.Instructions = insList;
})();