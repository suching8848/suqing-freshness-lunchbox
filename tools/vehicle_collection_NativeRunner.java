import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Actual LuaManager exposition and Java collections; no Cell/Vehicle/actor constructor. */
public final class vehicle_collection_NativeRunner {
    static Class<?> tableClass;
    static Object environment;
    interface Call { Object[] run(Object[] values) throws Exception; }
    static void put(String key,Object value) throws Exception {
        tableClass.getMethod("rawset",Object.class,Object.class).invoke(environment,key,value);
    }
    static void function(String name,Call callback) throws Exception {
        Class<?> fn=Class.forName("se.krka.kahlua.vm.JavaFunction");
        Object proxy=Proxy.newProxyInstance(fn.getClassLoader(),new Class<?>[]{fn},(self,method,args)->{
            if(method.getName().equals("call")) {
                Object frame=args[0];int count=(Integer)args[1];Object[] values=new Object[count];
                for(int i=0;i<count;i++) values[i]=frame.getClass().getMethod("get",int.class).invoke(frame,i);
                Object[] result=callback.run(values);
                for(Object value:result) frame.getClass().getMethod("push",Object.class).invoke(frame,value);
                return result.length;
            }
            if(method.getName().equals("toString"))return name;
            if(method.getName().equals("hashCode"))return System.identityHashCode(self);
            if(method.getName().equals("equals"))return self==args[0];
            return null;
        });
        put(name,proxy);
    }
    public static void main(String[] args) throws Exception {
        Class<?> filesystem=Class.forName("zombie.ZomboidFileSystem");
        filesystem.getMethod("init").invoke(filesystem.getField("instance").get(null));
        // LuaManager's normal exposition initializes ServerOptions; its defaults
        // require the two RNG services even though no client/world is started.
        for(String name:new String[]{"RandStandard","RandLua"}) {
            Class<?> random=Class.forName("zombie.core.random."+name);
            random.getMethod("init").invoke(random.getField("INSTANCE").get(null));
        }
        Class<?> manager=Class.forName("zombie.Lua.LuaManager");
        manager.getMethod("init").invoke(null);
        tableClass=Class.forName("se.krka.kahlua.vm.KahluaTable");
        environment=manager.getField("env").get(null);
        Object thread=manager.getField("thread").get(null);
        Object exposer=manager.getField("exposer").get(null);
        Method shouldExpose=exposer.getClass().getMethod("shouldExpose",Class.class);
        for(Class<?> type:new Class<?>[]{HashSet.class,ArrayList.class,Iterator.class}) {
            if(!Boolean.TRUE.equals(shouldExpose.invoke(exposer,type)))
                throw new AssertionError("Not exposed by current LuaManager: "+type);
        }
        if(!Set.class.isAssignableFrom(Class.forName("zombie.iso.IsoCell").getMethod("getVehicles").getReturnType()))
            throw new AssertionError("Current IsoCell.getVehicles no longer returns Set");
        put("VehicleCollectionExpectLegacyFailure",Boolean.valueOf(args[3]));
        function("VehicleCollectionMakeSet",v->new Object[]{new HashSet<Object>()});
        function("VehicleCollectionMakeList",v->new Object[]{new ArrayList<Object>()});
        function("VehicleCollectionPrint",v->{for(Object value:v)System.out.println(value);return new Object[0];});
        Method compile=Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler")
            .getMethod("loadstring",String.class,String.class,tableClass);
        Method call=thread.getClass().getMethod("pcall",Object.class,Object[].class);
        // Bootstrap, unmodified selected runtime, cases. Nothing loads a Lua directory.
        for(int i:new int[]{0,1,2}) {
            String path=args[i];
            Object closure=compile.invoke(null,new String(Files.readAllBytes(Paths.get(path)),StandardCharsets.UTF_8),path,environment);
            Object[] result=(Object[])call.invoke(thread,closure,new Object[0]);
            if(!Boolean.TRUE.equals(result[0]))throw new AssertionError(path+": "+Arrays.toString(result));
            if(result.length>1&&result[1] instanceof String)System.out.println(result[1]);
        }
        Object world=Class.forName("zombie.iso.IsoWorld").getField("instance").get(null);
        if(world!=null&&world.getClass().getField("currentCell").get(world)!=null)
            throw new AssertionError("Unexpected loaded world cell");
        System.out.println("VEHICLE_COLLECTION_ENV collection=java.util.HashSet exposition=LuaManager.Exposer world_cell_created=false vehicle_constructed=false actor_constructed=false game_started=false");
    }
}
