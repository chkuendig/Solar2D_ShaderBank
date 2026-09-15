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
  simulator compiles them as desktop GLSL, which is lenient in two ways ES is
  not: it gives floats a default precision, and it allows a global to be
  initialised from a uniform. Browsers and real devices reject both, so *no*
  shader compiled in the first web build. The shim declares a default precision
  and moves those initialisers to the top of the kernel function, on the way to
  `graphics.defineEffect` and only on ES targets — the shader files are left
  exactly as their authors wrote them.

Known limitation: about 50 of the 134 generator shaders still fail to compile in
a browser, on top of the two issues above — mixing `int` and `float` (`1 / uv`,
`for (int i; i < 10.0; ...)`) and initialising `uniform`s, which desktop GLSL
accepts and GLSL ES does not. They are per-shader source problems, not build
problems, and they would fail on iOS and Android for the same reason. Every
filter, transition and composite shader compiles.

Nothing else in the app differs from upstream.

Shader viewer with real-time texture swapping and param tweaking features provided, plus collections of abounding Solar2D-ready shaders. 

full operation could be done purely by touching UI or keyboard input solely, no problem with using them both simultaneously of course.

NOTE: Almost of the shaders are working on simulator but havn't test on devices yet, currently I'm replacing some variables to vertexData in the shaders. if you encounter bugs on the shader viewer, just let me know :)


You might want to check the license of thier original creators if you gonna to use them in your projects. the information included in each shader.lua file.

Screenshots:

![alt text](https://github.com/fenixn0909/Solar2D_ShaderBank/blob/main/_img/screenCap1.jpg?raw=true)

![alt text](https://github.com/fenixn0909/Solar2D_ShaderBank/blob/main/_img/screenCap2.jpg?raw=true)

![alt text](https://github.com/fenixn0909/Solar2D_ShaderBank/blob/main/_img/screenCap3.jpg?raw=true)














