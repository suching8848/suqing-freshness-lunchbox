import java.lang.reflect.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import sun.misc.Unsafe;

/** Actual native item methods in an isolated profile. No client, IsoWorld or save is loaded. */
public class runtime_NativeProbe {
    static Unsafe unsafe;
    static Class<?> foodClass,boxClass,containerClass,itemClass,scriptClass,tableClass;
    static Object time,environment;
    static int serial=2000;
    interface Call {Object[] run(Object[] args)throws Exception;}
    static Field field(Class<?> type,String name)throws Exception {
        for(Class<?> c=type;c!=null;c=c.getSuperclass())try{Field f=c.getDeclaredField(name);f.setAccessible(true);return f;}catch(NoSuchFieldException ignored){}
        throw new NoSuchFieldException(name);
    }
    static void set(Object o,String key,Object value)throws Exception{field(o.getClass(),key).set(o,value);}
    static void initItem(Object item,String module,String type)throws Exception{
        set(item,"module",module);set(item,"type",type);set(item,"fullType",module+"."+type);set(item,"id",++serial);
        set(item,"name","Native regression food");set(item,"originalName","Native regression food");set(item,"actualWeight",1f);
        set(item,"scriptItem",scriptClass.getConstructor().newInstance());
        set(item,"condition",10);set(item,"conditionMax",10);
        set(item,"col",Class.forName("zombie.core.Color").getField("white").get(null));
        set(item,"colorRed",1f);set(item,"colorGreen",1f);set(item,"colorBlue",1f);
        set(item,"itemCapacity",-1f);set(item,"wetCooldown",-1f);set(item,"keyId",-1);set(item,"remoteControlId",-1);
    }
    static Object box(String fullType)throws Exception{
        Object b=unsafe.allocateInstance(boxClass);int split=fullType.lastIndexOf('.');initItem(b,fullType.substring(0,split),fullType.substring(split+1));
        Object inner=containerClass.getConstructor().newInstance();set(inner,"containingItem",b);set(inner,"type","container");
        set(b,"container",inner);set(b,"capacity",4);set(b,"weightReduction",50);containerClass.getMethod("setCapacity",int.class).invoke(inner,4);return b;
    }
    static Object food(double age,int fresh,int rotten,String replacement)throws Exception{
        Object f=unsafe.allocateInstance(foodClass);initItem(f,"Base","Apple");
        set(f,"offAge",fresh);set(f,"offAgeMax",rotten);set(f,"age",(float)age);
        set(f,"lastAged",((Double)time.getClass().getMethod("getWorldAgeHours").invoke(time)).floatValue());
        set(f,"heat",1f);set(f,"freezingTime",0f);set(f,"hungChange",-0.15f);set(f,"baseHunger",-0.3f);
        set(f,"calories",168f);set(f,"stressChange",-0.12f);set(f,"endChange",0.15f);set(f,"unhappyChange",2f);set(f,"boredomChange",3f);
        set(f,"carbohydrates",17f);set(f,"lipids",8f);set(f,"proteins",4f);set(f,"cooked",true);set(f,"isTainted",true);set(f,"poisonPower",12);
        set(f,"replaceOnRotten",replacement);
        for(String[] pair:new String[][]{{"freshString","Fresh"},{"staleString","Stale"},{"offString","Rotten"},{"cookedString","Cooked"},{"unCookedString","Uncooked"},{"burntString","Burnt"},{"frozenString","Frozen"},{"grilledString","Grilled"},{"toastedString","Toasted"}})set(f,pair[0],pair[1]);
        return f;
    }
    static void put(String name,Object value)throws Exception{tableClass.getMethod("rawset",Object.class,Object.class).invoke(environment,name,value);}
    static void function(String name,Call callback)throws Exception{
        Class<?> fn=Class.forName("se.krka.kahlua.vm.JavaFunction");
        Object proxy=Proxy.newProxyInstance(fn.getClassLoader(),new Class<?>[]{fn},(self,m,args)->{
            if(m.getName().equals("call")){
                Object frame=args[0];int count=(Integer)args[1];Object[] values=new Object[count];
                for(int i=0;i<count;i++)values[i]=frame.getClass().getMethod("get",int.class).invoke(frame,i);
                Object[] result=callback.run(values);
                for(Object v:result)frame.getClass().getMethod("push",Object.class).invoke(frame,v);
                return result.length;
            }
            if(m.getName().equals("toString"))return name;
            if(m.getName().equals("hashCode"))return System.identityHashCode(self);
            if(m.getName().equals("equals"))return self==args[0];
            return null;
        });put(name,proxy);
    }
    public static void main(String[]args)throws Exception{
        Field uf=Unsafe.class.getDeclaredField("theUnsafe");uf.setAccessible(true);unsafe=(Unsafe)uf.get(null);
        Class<?> fs=Class.forName("zombie.ZomboidFileSystem");fs.getMethod("init").invoke(fs.getField("instance").get(null));
        for(String name:new String[]{"RandStandard","RandLua"}){Class<?> c=Class.forName("zombie.core.random."+name);c.getMethod("init").invoke(c.getField("INSTANCE").get(null));}
        Class<?> manager=Class.forName("zombie.Lua.LuaManager");manager.getMethod("init").invoke(null);
        Class<?> tc=Class.forName("zombie.GameTime");time=tc.getConstructor().newInstance();tc.getMethod("setInstance",tc).invoke(null,time);tc.getMethod("setTimeOfDay",float.class).invoke(time,12f);
        foodClass=Class.forName("zombie.inventory.types.Food");boxClass=Class.forName("zombie.inventory.types.InventoryContainer");
        containerClass=Class.forName("zombie.inventory.ItemContainer");itemClass=Class.forName("zombie.inventory.InventoryItem");scriptClass=Class.forName("zombie.scripting.objects.Item");tableClass=Class.forName("se.krka.kahlua.vm.KahluaTable");
        environment=manager.getField("env").get(null);Object thread=manager.getField("thread").get(null);put("ProbeTime",time);
        Class<?> sandbox=Class.forName("zombie.SandboxOptions");Object removal=field(sandbox,"daysForRottenFoodRemoval").get(sandbox.getField("instance").get(null));removal.getClass().getMethod("setValue",int.class).invoke(removal,-1);put("ProbeRemoval",removal);
        Class<?> translator=Class.forName("zombie.core.Translator");((Map<?,?>)field(translator,"ui").get(null)).clear();
        @SuppressWarnings("unchecked") Map<String,String> display=(Map<String,String>)field(translator,"igui").get(null);display.clear();display.put("IGUI_FoodNaming","%2 (%1)");
        function("ProbeMakeBox",v->new Object[]{box(v.length>0&&v[0]!=null?v[0].toString():"SuQingFreshnessLunchbox.FreshnessLunchbox")});
        function("ProbeMakeFood",v->new Object[]{food(((Number)v[0]).doubleValue(),((Number)v[1]).intValue(),((Number)v[2]).intValue(),v.length>3&&v[3]!=null?v[3].toString():null)});
        function("ProbeWearable",v->{Class<?> location=Class.forName("zombie.scripting.objects.ItemBodyLocation");boxClass.getMethod("setCanBeEquipped",location).invoke(v[0],location.getField("BACK").get(null));return new Object[0];});
        function("ProbeMakeFridge",v->{
            Class<?> oc=Class.forName("zombie.iso.IsoObject"),sc=Class.forName("zombie.iso.sprite.IsoSprite");
            Object object=oc.getConstructor().newInstance(),sprite=unsafe.allocateInstance(sc),container=containerClass.getConstructor().newInstance();
            set(sprite,"name","suqing_freshness_fridge_01_0");set(object,"sprite",sprite);set(container,"parent",object);set(container,"type","fridge");oc.getMethod("setContainer",containerClass).invoke(object,container);
            return new Object[]{object,container};
        });
        function("ProbeNativeAge",v->{foodClass.getMethod("updateAge",boolean.class).invoke(v[0],false);return new Object[0];});
        final Method rot=foodClass.getDeclaredMethod("updateRotting",containerClass);rot.setAccessible(true);
        function("ProbeNativeRot",v->{rot.invoke(v[0],v[1]);return new Object[0];});
        function("ProbeRoundTrip",v->{
            Object f=v[0];Object clone=food(((Float)foodClass.getMethod("getAge").invoke(f)).doubleValue(),(Integer)foodClass.getMethod("getOffAge").invoke(f),(Integer)foodClass.getMethod("getOffAgeMax").invoke(f),"Base.Compost");
            ByteBuffer bytes=ByteBuffer.allocate(65536);foodClass.getMethod("save",ByteBuffer.class,boolean.class).invoke(f,bytes,false);int size=bytes.position();bytes.flip();bytes.position(3);
            foodClass.getMethod("load",ByteBuffer.class,int.class).invoke(clone,bytes,249);
            if(bytes.position()!=size)throw new AssertionError("native save/load boundary mismatch "+bytes.position()+"/"+size);
            return new Object[]{clone,Double.valueOf(size)};
        });
        function("ProbePrint",v->{StringBuilder s=new StringBuilder();for(Object o:v){if(s.length()>0)s.append('\t');s.append(o);}System.out.println(s);return new Object[0];});
        Method load=Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler").getMethod("loadstring",String.class,String.class,tableClass);
        Method pcall=thread.getClass().getMethod("pcall",Object.class,Object[].class);
        for(String name:args){Object closure=load.invoke(null,new String(Files.readAllBytes(Paths.get(name)),StandardCharsets.UTF_8),name,environment);Object[] result=(Object[])pcall.invoke(thread,closure,new Object[0]);System.out.println(name+": "+Arrays.toString(result));if(!Boolean.TRUE.equals(result[0]))throw new AssertionError(Arrays.toString(result));}
        Object world=Class.forName("zombie.iso.IsoWorld").getField("instance").get(null);
        if(world!=null && field(world.getClass(),"currentCell").get(world)!=null)throw new AssertionError("world cell unexpectedly loaded");
        System.out.println("NATIVE_PROFILE game_started=false world_loaded=false world_cell_created=false singleton_initialized="+(world!=null));
    }
}
