import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.lang.reflect.Method;

/** Compile-only audit using the game's actual Kahlua compiler. */
public class runtime_LuaCompile {
    public static void main(String[] args) throws Exception {
        Class<?> table=Class.forName("se.krka.kahlua.vm.KahluaTable");
        Object platform=Class.forName("se.krka.kahlua.j2se.J2SEPlatform").newInstance();
        Object env=platform.getClass().getMethod("newEnvironment").invoke(platform);
        Method load=Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler").getMethod("loadstring",String.class,String.class,table);
        for(String name:args) load.invoke(null,new String(Files.readAllBytes(Paths.get(name)),StandardCharsets.UTF_8),name,env);
        System.out.println("RUNTIME_COMPILE files="+args.length+" PASS");
    }
}
