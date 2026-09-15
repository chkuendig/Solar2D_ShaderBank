--[[
    glsl_es <GLSL ES conformance shim>

    Makes the bank's shaders compile on OpenGL ES 2 / WebGL, which is what a
    browser or a device runs. The desktop simulator compiles them as desktop
    GLSL 1.10/1.20 and accepts two things ES rejects outright:

    1. Unqualified floats. Desktop GLSL gives every float a precision; ES gives
       fragment shaders none by default, and Solar2D's ES header only defines the
       P_* macros, so `float Progress = ...` is
           ERROR: '' : No precision specified for (float)
       Fixed by declaring a default precision, guarded by GL_ES so the desktop
       header — which #defines mediump to nothing — never sees it.

    2. Globals initialised from a uniform or varying:
           float Progress = CoronaVertexUserData.x;
       is
           ERROR: '=' : global variable initializers must be constant expressions
       ES only allows constant expressions there. The declaration stays where it
       is, without its initialiser, and the assignment moves to the top of the
       kernel function, which runs before anything can read it. Semantics are the
       same and the variable stays assignable, which a #define would not.


    3. Godot-style uniform defaults:
           uniform float speed = 2.0;
       is
           ERROR: 'uniform' : cannot initialize this type of qualifier
       and it is the most common reason a shader here fails in a browser. These
       came across with the ported source; Solar2D only binds what a kernel
       declares in vertexData/uniformData, so nothing can ever set them and they
       are defaults in all but name. The qualifier is dropped and the line is
       then treated as case 2.

    Nothing here rewrites a file on disk: the shaders are somebody else's work
    and stay as they were written. This runs over the kernel table on the way to
    graphics.defineEffect, and only on ES targets, so the simulator keeps
    compiling exactly the source the author wrote.
--]]

local M = {}

local kPrecision = "#ifdef GL_ES\nprecision mediump float;\n#endif\n"

-- Types whose declarations are worth touching. Samplers and structs are never
-- initialised at global scope in this bank.
local mtType = {
    float=true, vec2=true, vec3=true, vec4=true,
    mat2=true, mat3=true, mat4=true,
    int=true, ivec2=true, ivec3=true, ivec4=true,
    bool=true, bvec2=true, bvec3=true, bvec4=true,
}

-- Leading words that may sit in front of the type. A declaration carrying a
-- storage qualifier is left alone: const must keep its initialiser, and
-- uniform/varying/attribute cannot have one to begin with.
local mtPrecQual = { P_DEFAULT=true, P_RANDOM=true, P_POSITION=true, P_NORMAL=true, P_UV=true, P_COLOR=true,
                     lowp=true, mediump=true, highp=true }
local mtStorage  = { const=true, uniform=true, varying=true, attribute=true, ["in"]=true, ["out"]=true }

local lines_of = function( s_ )
    local _a = {}
    for line in ( s_ .. "\n" ):gmatch( "([^\n]*)\n" ) do    _a[#_a+1] = line     end
return _a    end

--=== Split "P_COLOR vec4 name = rest;" into its parts. nil when the line is not
--    a single initialised declaration of a known type.
local parse_decl = function( sLine_ )
    local _code = sLine_:match( "^(.-)//" ) or sLine_          -- ignore a trailing comment
    local _decl, _init = _code:match( "^%s*(.-)%s*=%s*(.-)%s*;%s*$" )
    if not _decl then    return nil     end
    -- A multi-declarator line ("float a, b = 1.0;") carries its comma in the
    -- declaration, not the initialiser. Testing the initialiser instead rejected
    -- every constructor default -- vec4( 1.0, .95, .75, 1.0 ) and friends -- which
    -- is most of what the ported shaders declare.
    if _init == "" or _decl:find( ",", 1, true ) then    return nil     end

    local _words = {}
    for w in _decl:gmatch( "[%w_%[%]]+" ) do    _words[#_words+1] = w     end
    if #_words < 2 then    return nil     end

    local _name = _words[#_words]
    local _type = _words[#_words-1]
    if not mtType[_type] or _name:find( "%[" ) then    return nil     end     -- arrays cannot be assigned as a whole in ES 2

    for i=1, #_words-2 do
        if mtStorage[ _words[i] ] then    return nil     end
        if not mtPrecQual[ _words[i] ] then    return nil     end             -- anything unexpected: leave the line alone
    end

return _decl, _name, _init    end

--=== "uniform float speed = 2.0;" — the Godot way of writing a default. ES
--    rejects it outright ("cannot initialize this type of qualifier"), and it is
--    the single largest reason shaders in this bank do not compile in a browser.
--    Nothing can set these from Lua: Solar2D only wires up what a kernel declares
--    in vertexData/uniformData, and these names came across with the ported
--    source, so they are defaults and nothing else. Dropping the qualifier leaves
--    an ordinary global with the same value, which the hoist below then handles.
--    Returns nil unless the result is a plain initialised declaration, so arrays,
--    samplers and multi-declarator lines keep their qualifier and stay as-is.
local strip_uniform_default = function( sLine_ )
    local _indent, _rest = sLine_:match( "^(%s*)uniform%s+(.*)$" )
    if not _rest then    return nil     end
    local _code = _rest:match( "^(.-)//" ) or _rest
    if not _code:find( "=", 1, true ) then    return nil     end   -- a real uniform: leave it alone
return _indent .. _rest    end

--=== "float freq = 10;" — desktop GLSL promotes the literal, ES does not
--    ("cannot convert from 'const int' to 'mediump float'"). Only a float
--    declaration handed a bare integer literal is touched, so an int stays an
--    int and arithmetic elsewhere on the line is left alone.
local fix_int_literal = function( sLine_ )
    local _pre, _name, _lit, _post = sLine_:match( "^(.-)float%s+([%w_]+)%s*=%s*(%-?%d+)%s*;(.*)$" )
    if not _pre then    return nil     end
    if _pre ~= "" and not _pre:match( "%s$" ) then    return nil     end   -- "myfloat", not the keyword
    for w in _pre:gmatch( "[%w_]+" ) do
        if not ( mtPrecQual[w] or mtStorage[w] ) then    return nil     end
    end
return _pre .. "float " .. _name .. " = " .. _lit .. ".0;" .. _post    end

--=== Bare integer literals in float arithmetic: "uv * 2", "1 - d". Desktop GLSL
--    promotes them, ES does not, and this is now the single biggest reason a
--    shader here fails. Promotion is only safe where the line does no integer
--    work of its own, so a line is skipped whole if it mentions an integer type,
--    subscripts an array, drives a loop, or is a preprocessor directive --- in
--    any of those a promoted literal would break something that compiles today.
local mtIntWord = { int=true, ivec2=true, ivec3=true, ivec4=true }

local fix_int_arith = function( sLine_, mtIntName_ )
    local _code, _cmt = sLine_:match( "^(.-)(//.*)$" )
    if not _code then    _code, _cmt = sLine_, ""     end

    if _code:find( "#", 1, true ) then    return nil     end
    if _code:find( "[", 1, true ) then    return nil     end
    if _code:find( "for", 1, true ) then    return nil     end
    if _code:find( "%d[eE][-+]?%d" ) then    return nil     end        -- exponents: splitting one corrupts it
    for w in _code:gmatch( "[%a_][%w_]*" ) do
        if mtIntName_ and mtIntName_[w] then    return nil     end
        if mtIntWord[w] then    return nil     end
    end

    local _out, _i, _n, _bChanged = {}, 1, #_code, false
    while _i <= _n do
        local _c = _code:sub( _i, _i )
        if _c:match( "%d" ) then
            local _prev = _i > 1 and _code:sub( _i-1, _i-1 ) or ""
            local _s = _i
            if _prev:match( "[%w_%.]" ) then                           -- inside an identifier or a float
                while _i <= _n and _code:sub( _i, _i ):match( "[%w_%.]" ) do    _i = _i + 1     end
                _out[#_out+1] = _code:sub( _s, _i-1 )
            else
                while _i <= _n and _code:sub( _i, _i ):match( "%d" ) do    _i = _i + 1     end
                local _nxt = _code:sub( _i, _i )
                if _nxt == "." or _nxt:match( "[%w_]" ) then           -- already a float, or part of a name
                    while _i <= _n and _code:sub( _i, _i ):match( "[%w_%.]" ) do    _i = _i + 1     end
                    _out[#_out+1] = _code:sub( _s, _i-1 )
                else
                    _out[#_out+1] = _code:sub( _s, _i-1 ) .. ".0"
                    _bChanged = true
                end
            end
        else
            _out[#_out+1] = _c
            _i = _i + 1
        end
    end
    if not _bChanged then    return nil     end
return table.concat( _out ) .. _cmt    end

--=== Names declared as an integer anywhere in this stage. A line that so much as
--    mentions one is left alone: "mode == 1" is correct where mode is an int, and
--    promoting that literal is what turns a working shader into a broken one.
local collect_int_names = function( aLine_ )
    local _mt = {}
    for i=1, #aLine_ do
        local _code = aLine_[i]:match( "^(.-)//" ) or aLine_[i]
        local _w = {}
        for t in _code:gmatch( "[%a_][%w_]*" ) do    _w[#_w+1] = t     end
        for k=1, #_w-1 do
            if mtIntWord[ _w[k] ] then    _mt[ _w[k+1] ] = true     end
        end
    end
return _mt    end

--=== Rewrite one shader stage. Returns nil when there is nothing to change.
local rewrite = function( sSrc_, sKernel_ )
    if type( sSrc_ ) ~= "string" then    return nil     end

    local _aLine = lines_of( sSrc_ )
    local _mtIntName = collect_int_names( _aLine )

    -- Whole-source pass: this one is not about scope, so it runs over every line.
    for i=1, #_aLine do
        local _fixed = fix_int_literal( _aLine[i] )
        if not _fixed then    _fixed = fix_int_arith( _aLine[i], _mtIntName )     end
        if _fixed then    _aLine[i] = _fixed     end
    end

    -- Where the kernel function's body starts; everything before it is global scope.
    local _iKernel, _iBrace
    for i=1, #_aLine do
        if _aLine[i]:find( sKernel_, 1, true ) then    _iKernel = i; break     end
    end
    if _iKernel then
        for i=_iKernel, #_aLine do
            if _aLine[i]:find( "{", 1, true ) then    _iBrace = i; break     end
        end
    end

    local _aMoved = {}
    if _iBrace then
        -- Only true global scope. Plenty of these shaders define helper functions
        -- above the kernel, and a local inside one of those must stay where it is:
        -- hoisting it would move the assignment out of the scope of everything it
        -- reads. Brace depth is what tells the two apart.
        local _depth, _bBlockComment = 0, false
        for i=1, _iKernel-1 do
            local _code, _line = "", _aLine[i]
            -- strip comments before counting braces, so a { in prose does not count
            while #_line > 0 do
                if _bBlockComment then
                    local _e = _line:find( "*/", 1, true )
                    if not _e then    _line = ""
                    else    _bBlockComment = false; _line = _line:sub( _e+2 )     end
                else
                    local _s = _line:find( "/*", 1, true )
                    local _l = _line:find( "//", 1, true )
                    if _l and ( not _s or _l < _s ) then    _code = _code .. _line:sub( 1, _l-1 ); _line = ""
                    elseif _s then    _code = _code .. _line:sub( 1, _s-1 ); _bBlockComment = true; _line = _line:sub( _s+2 )
                    else    _code = _code .. _line; _line = ""     end
                end
            end

            if _depth == 0 then
                -- A Godot-style default has to lose its qualifier before it can be read
                -- as a declaration at all; commit that only if the result parses.
                local _cand = strip_uniform_default( _aLine[i] )
                if _cand and parse_decl( _cand ) then    _aLine[i] = _cand     end
                local _decl, _name, _init = parse_decl( _aLine[i] )
                if _decl then
                    local _comment = _aLine[i]:match( "(%s*//.*)$" ) or ""
                    _aLine[i] = _decl .. ";" .. _comment
                    _aMoved[#_aMoved+1] = "    " .. _name .. " = " .. _init .. ";"
                end
            end

            for _ in _code:gmatch( "{" ) do    _depth = _depth + 1     end
            for _ in _code:gmatch( "}" ) do    _depth = _depth - 1     end
        end
        if #_aMoved > 0 then
            _aLine[_iBrace] = _aLine[_iBrace] .. "\n" .. table.concat( _aMoved, "\n" )
        end
    end

return kPrecision .. table.concat( _aLine, "\n" )    end

--=== True when this target compiles GLSL ES: a device or a browser. The
--    simulator is desktop GL and needs none of this.
M.is_needed = function()
return system.getInfo( "environment" ) ~= "simulator"    end

--=== Rewrite a kernel table in place and return it, so it can wrap a call.
M.normalize = function( tKernel_ )
    if type( tKernel_ ) ~= "table" or not M.is_needed() then    return tKernel_     end

    local _frag = rewrite( tKernel_.fragment, "FragmentKernel" )
    if _frag then    tKernel_.fragment = _frag     end

    local _vert = rewrite( tKernel_.vertex, "VertexKernel" )
    if _vert then    tKernel_.vertex = _vert     end

return tKernel_    end

return M
