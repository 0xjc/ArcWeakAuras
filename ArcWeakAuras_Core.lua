-- ArcWeakAuras Core 2.0.0 (https://github.com/0xjc/ArcWeakAuras)
function aura_env:InitArcTSU(a)if a=="basic"then self.TSU=function(b,c,d,...)local e=b[d]if e then e(b,...)c[""]=b;return b.changed end end elseif a=="multi"then self.TSU=function(b,c,d,...)local e=b[d]if e then b.allStates=c;return e(b,...)end end else error("invalid tsuMode")end end
-- End of ArcWeakAuras Core
