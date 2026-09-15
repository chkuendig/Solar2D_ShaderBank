# Solar2D_ShaderBank

**This fork publishes the viewer as a website:**
**https://christian.kuendig.info/Solar2D_ShaderBank/** — every shader in the bank,
filterable and linked to its source, plus the viewer itself running in the browser.

`.github/workflows/pages.yml` builds it on every push to `main`. Solar2D ships no
Linux HTML5 packager, so the build runs inside
[`ghcr.io/chkuendig/solar2d`](https://github.com/chkuendig/docker-solar2d), a
container carrying a Solar2D fork with the Linux build gates opened. Three small
changes to the app make the packaged build work:

- `tools/gen-shader-manifest.sh` writes the shader list at build time. The app
  discovers shaders with `lfs.dir()`, which only finds them in the simulator — any
  packaged build (HTML5, Android, iOS) compiles the `.lua` files into
  `resource.car`, so the listing comes back empty and every category is empty with
  it. `main.lua` prefers the manifest when it exists and still uses `lfs.dir()` in
  the simulator.
- The `_mcp_*` helpers are now required in the simulator only. They talk to the
  MCP server through files in the host's temp folder, which a browser build cannot
  reach.
- `_plugin/glsl_es.lua` makes the shaders compile on WebGL. The desktop
  simulator compiles them as desktop GLSL, which is lenient in several ways ES
  is not, and *no* shader compiled in the first web build. The shim rewrites the
  kernel table on the way to `graphics.defineEffect`, and only on ES targets, so
  the shader files are left exactly as their authors wrote them. It covers:
  - no default float precision in ES fragment shaders;
  - globals initialised from a uniform or varying, which ES requires to be
    constant expressions — the assignment moves to the top of the kernel;
  - Godot-style `uniform float speed = 2.0;` defaults, which ES rejects outright
    and which nothing can set from Lua anyway;
  - bare integer literals in float arithmetic (`uv * 2`, `float freq = 10`),
    which desktop GLSL promotes and ES does not. Lines that do genuine integer
    work — a loop header, an array subscript, anything naming an int variable —
    are left alone.

Known limitation: 59 of the 451 shaders still fail to compile in a browser, and
they would fail on iOS and Android for the same reason. Almost all of it is
GLSL ES 1.00's restrictions on loops (`Loop index cannot be compared with
non-constant expression`, `Index expression can only contain const or loop
symbols`) and array constructors that need ES 3.00. Those are per-shader source
problems that no build-time shim can paper over.

Nothing else in the app differs from upstream.

Shader viewer with real-time texture swapping and param tweaking features provided, plus collections of abounding Solar2D-ready shaders. 

full operation could be done purely by touching UI or keyboard input solely, no problem with using them both simultaneously of course.

NOTE: Almost of the shaders are working on simulator but havn't test on devices yet, currently I'm replacing some variables to vertexData in the shaders. if you encounter bugs on the shader viewer, just let me know :)


You might want to check the license of thier original creators if you gonna to use them in your projects. the information included in each shader.lua file.

Screenshots:

![alt text](https://github.com/fenixn0909/Solar2D_ShaderBank/blob/main/_img/screenCap1.jpg?raw=true)

![alt text](https://github.com/fenixn0909/Solar2D_ShaderBank/blob/main/_img/screenCap2.jpg?raw=true)

![alt text](https://github.com/fenixn0909/Solar2D_ShaderBank/blob/main/_img/screenCap3.jpg?raw=true)














