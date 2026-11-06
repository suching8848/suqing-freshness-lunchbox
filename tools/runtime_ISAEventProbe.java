import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
/** Real native Event Add/Remove/trigger, actual item methods; no world cell. */
public class runtime_ISAEventProbe extends runtime_NativeProbe {
    public static void main(String[]args)throws Exception{
        runtime_NativeProbe.main(new String[0]);
        Class<?> manager=Class.forName("zombie.Lua.LuaManager"),eventManager=Class.forName("zombie.Lua.LuaEventManager"),eventClass=Class.forName("zombie.Lua.Event");
        Object caller=manager.getField("caller").get(null);
        function("NativeEmit",values->{
            @SuppressWarnings("unchecked") Map<String,Object> map=(Map<String,Object>)field(eventManager,"EventMap").get(null);
            Object event=map.get(values[0].toString());if(event==null)throw new AssertionError("missing actual native event");
            eventClass.getMethod("trigger",tableClass,Class.forName("se.krka.kahlua.integration.LuaCaller"),Object[].class).invoke(event,environment,caller,new Object[0]);
            return new Object[0];
        });
        Object thread=manager.getField("thread").get(null);
        Method compile=Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler").getMethod("loadstring",String.class,String.class,tableClass),call=thread.getClass().getMethod("pcall",Object.class,Object[].class);
        for(String name:args){
            Object closure=compile.invoke(null,new String(Files.readAllBytes(Paths.get(name)),StandardCharsets.UTF_8),name,environment);
            Object[] result=(Object[])call.invoke(thread,closure,new Object[0]);
            if(!Boolean.TRUE.equals(result[0]))throw new AssertionError(name+": "+Arrays.toString(result));
            if(result.length>1&&result[1] instanceof String)System.out.println(result[1]);
        }
        Object world=Class.forName("zombie.iso.IsoWorld").getField("instance").get(null);
        if(world!=null&&field(world.getClass(),"currentCell").get(world)!=null)throw new AssertionError("world cell unexpectedly loaded");
    }
}
