/* utils.js */
(function() {
    window.MiniSys = window.MiniSys || {};
    
    // 模拟 Node.js 的 assert
    function assert(condition, message) {
        if (!condition) {
            throw new Error(message || "Assertion failed");
        }
    }

    class SeuError extends Error {
        constructor(message) {
            super(message);
            this.name = 'SeuError';
        }
    }

    const Utils = {
        SeuError: SeuError,
        assert: assert,

        // 十进制转二进制 (补码支持)
        decToBin: (dec, len) => {
            return (dec >>> 0).toString(2).padStart(len, '0').slice(-len);
        },

        // 二进制转十六进制 (大写)
        binToHex: (bin, prefix=false) => {
            let hex = parseInt(bin, 2).toString(16).toUpperCase().padStart(Math.ceil(bin.length / 4), '0');
            return prefix ? '0x' + hex : hex;
        },

        // 十六进制转十进制
        hexToDec: (hex) => {
            return parseInt(hex, 16);
        },
        
        // 十六进制转二进制
        hexToBin: (hex) => {
            if (hex.startsWith('0x')) hex = hex.substring(2);
            return parseInt(hex, 16).toString(2).padStart(hex.length * 4, '0');
        },

        // 规范化字符串 (移除所有空白)
        serialString: (str) => {
            return str.replace(/\s+/g, '');
        },

        // 获取类型大小
        sizeof: (type) => {
            const map = { byte: 1, half: 2, word: 4, space: 1, ascii: 1, ins: 4 };
            const size = map[type];
            if (size === undefined) throw new SeuError(`错误的变量类型：${type}`);
            return size;
        },

        // 立即数转二进制
        literalToBin: (literal, len) => {
            let val = literal.trim();
            let num = val.startsWith('0x') ? parseInt(val, 16) : parseInt(val, 10);
            return Utils.decToBin(num, len);
        },
        
        // 标签占位符
        labelToBin: (label, len, offset) => {
            // 返回一个对象，标识这里需要后续填入地址
            return { isLabel: true, name: label, len: len, offset: offset };
        }
    };

    window.MiniSys.Utils = Utils;
})();