import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.Arrays;

/** Pure Kahlua regression: actual bridge/vanilla Lua plus deterministic API shells. */
public final class attachments_KahluaRunner {
    public static void main(String[] args) throws Exception {
        Class<?> platformClass=Class.forName("se.krka.kahlua.j2se.J2SEPlatform");
        Object platform=platformClass.getConstructor().newInstance();
        Object env=platformClass.getMethod("newEnvironment").invoke(platform);
        Class<?> tableClass=Class.forName("se.krka.kahlua.vm.KahluaTable");
        Class<?> threadClass=Class.forName("se.krka.kahlua.vm.KahluaThread");
        Object thread=threadClass.getConstructor(Class.forName("se.krka.kahlua.vm.Platform"),tableClass).newInstance(platform,env);
        threadClass.getField("debugOwnerThread").set(thread,Thread.currentThread());
        Method compile=Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler").getMethod("loadstring",String.class,String.class,tableClass);
        Method set=tableClass.getMethod("rawset",Object.class,Object.class);
        Method run=threadClass.getMethod("pcall",Object.class,Object[].class);
        String[] names={"AttachmentBridgeChunk","VanillaAttachmentDefinitionsChunk"};
        for(int i=0;i<2;i++) {
            String source=new String(Files.readAllBytes(Paths.get(args[i])),StandardCharsets.UTF_8);
            Object closure=compile.invoke(null,source,args[i],env);
            set.invoke(env,names[i],closure);
        }
        String file=args[2];
        Object closure=compile.invoke(null,new String(Files.readAllBytes(Paths.get(file)),StandardCharsets.UTF_8),file,env);
        Object[] result=(Object[])run.invoke(thread,closure,new Object[0]);
        if(!Boolean.TRUE.equals(result[0])) throw new AssertionError(Arrays.toString(result));
        if(result.length>1) System.out.println(result[1]);
    }
}
