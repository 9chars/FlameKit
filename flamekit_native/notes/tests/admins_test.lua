package.path = arg[1] .. "/?.lua;" .. package.path
local saved = {}
package.loaded["core.store"] = { load = function(k, d) return saved[k] or d end, save = function(k, v) saved[k] = v end }
local a = require("core.admins")
assert(a.is("0x485890b753e75ad1") == true, "owner is admin by default")
assert(a.is("0x1") == false, "stranger is not")
assert(a.is("0x1", { admin = true }) == true, "EMF admin")
assert(a.is(nil, { is_local = true }) == true, "host")
print("ALL PASSED (admins)")
