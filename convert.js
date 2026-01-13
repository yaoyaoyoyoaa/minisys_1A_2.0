/* convert.js */
(function() {
    window.MiniSys = window.MiniSys || {};
    const Utils = window.MiniSys.Utils;

    function textSegToCoe(textSeg) {
        let binaries = textSeg.ins; // Array of 32-bit bin strings
        
        let output = "memory_initialization_radix=16;\nmemory_initialization_vector=\n";
        
        binaries.forEach((bin, i) => {
            let hex = Utils.binToHex(bin);
            output += hex;
            if (i < binaries.length - 1) output += ",\n";
            else output += ";";
        });
        
        return output;
    }

    window.MiniSys.Convert = { textSegToCoe };
})();