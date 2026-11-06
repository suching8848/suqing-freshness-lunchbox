import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.Arrays;
/** Independent parser/model regression runner; no world, character or client. */
public final class integration_KahluaRunner {
    public static void main(String[]args)throws Exception{
        Class<?> platformClass=Class.forName("se.krka.kahlua.j2se.J2SEPlatform");
        Object platform=platformClass.getConstructor().newInstance(),env=platformClass.getMethod("newEnvironment").invoke(platform);
        Class<?> table=Class.forName("se.krka.kahlua.vm.KahluaTable"), threadClass=Class.forName("se.krka.kahlua.vm.KahluaThread");
        Object thread=threadClass.getConstructor(Class.forName("se.krka.kahlua.vm.Platform"),table).newInstance(platform,env);
        threadClass.getField("debugOwnerThread").set(thread,Thread.currentThread());
        Method compile=Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler").getMethod("loadstring",String.class,String.class,table);
        Method run=threadClass.getMethod("pcall",Object.class,Object[].class);
        boolean compileOnly=args.length>0&&args[0].equals("--compile");int compiled=0;
        for(int i=compileOnly?1:0;i<args.length;i++){
            String file=args[i];
            Object closure=compile.invoke(null,new String(Files.readAllBytes(Paths.get(file)),StandardCharsets.UTF_8),file,env);
            if(compileOnly){compiled++;continue;}
            Object[] result=(Object[])run.invoke(thread,closure,new Object[0]);
            if(!Boolean.TRUE.equals(result[0]))throw new AssertionError(file+": "+Arrays.toString(result));
            if(result.length>1&&result[1] instanceof String)System.out.println(result[1]);
        }
        if(compileOnly)System.out.println("INTEGRATION_COMPILE files="+compiled+" failures=0");
    }
}
