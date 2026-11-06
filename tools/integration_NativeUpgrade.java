import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.Arrays;

/** Native inventory/setter/material methods; only actor and recipe-data are Lua shells. */
public class integration_NativeUpgrade extends runtime_NativeProbe {
    public static void main(String[]args)throws Exception {
        runtime_NativeProbe.main(new String[0]);
        function("IntegrationMakeInventory",v->new Object[]{containerClass.getConstructor().newInstance()});
        function("IntegrationMakeMaterial",v->{
            String full=v[0].toString();Class<?> cls=full.equals("Base.Thread")?Class.forName("zombie.inventory.types.DrainableComboItem"):itemClass;
            Object material=unsafe.allocateInstance(cls);int split=full.indexOf('.');initItem(material,full.substring(0,split),full.substring(split+1));
            if(full.equals("Base.Thread")){set(material,"useDelta",0.05f);set(material,"uses",20);set(material,"weightEmpty",0f);}
            if(full.equals("Base.Screwdriver")){
                Object script=field(material.getClass(),"scriptItem").get(material);
                @SuppressWarnings("unchecked") java.util.Set<Object> tags=(java.util.Set<Object>)scriptClass.getMethod("getTags").invoke(script);
                tags.add(Class.forName("zombie.scripting.objects.ItemTag").getField("SCREWDRIVER").get(null));
            }
            return new Object[]{material};
        });
        function("IntegrationMakeScript",v->{
            String full=v[0].toString();int split=full.indexOf('.');Class<?> moduleClass=Class.forName("zombie.scripting.objects.ScriptModule");
            Object module=moduleClass.getConstructor().newInstance();moduleClass.getField("name").set(module,full.substring(0,split));
            Object script=scriptClass.getConstructor().newInstance();scriptClass.getMethod("setModule",moduleClass).invoke(script,module);
            scriptClass.getMethod("Load",String.class,String.class).invoke(script,full.substring(split+1),"item "+full.substring(split+1)+" { ItemType = Container, Weight = 1, Capacity = 49, WeightReduction = 99, }");
            return new Object[]{script};
        });
        function("IntegrationMakeEXRecipe",v->{
            String shortName=v[0].toString();Object root=integration_NativeAudit.parse(Paths.get(System.getProperty("integration.exRecipes")));
            Object moduleBlock=integration_NativeAudit.first(root);Class<?> block=root.getClass(),rc=Class.forName("zombie.scripting.entity.components.crafting.CraftRecipe"),mc=Class.forName("zombie.scripting.objects.ScriptModule");
            Object module=mc.getConstructor().newInstance();mc.getField("name").set(module,"ExSuQingBackpackSuperUpgrade");
            for(Object candidate:(java.util.List<?>)block.getField("children").get(moduleBlock)){
                if(shortName.equals(block.getField("id").get(candidate))){Object recipe=rc.getConstructor().newInstance();rc.getMethod("setModule",mc).invoke(recipe,module);field(rc,"scriptObjectName").set(recipe,shortName);rc.getMethod("Load",String.class,block).invoke(recipe,shortName,candidate);return new Object[]{recipe};}
            }
            throw new AssertionError("EX native recipe not found: "+shortName);
        });
        Object thread=Class.forName("zombie.Lua.LuaManager").getField("thread").get(null);
        Method compile=Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler").getMethod("loadstring",String.class,String.class,tableClass);
        Method call=thread.getClass().getMethod("pcall",Object.class,Object[].class);
        for(String name:args){
            Object closure=compile.invoke(null,new String(Files.readAllBytes(Paths.get(name)),StandardCharsets.UTF_8),name,environment);
            Object[] result=(Object[])call.invoke(thread,closure,new Object[0]);
            if(!Boolean.TRUE.equals(result[0]))throw new AssertionError(name+": "+Arrays.toString(result));
            if(result.length>1&&result[1] instanceof String)System.out.println(result[1]);
        }
        Object world=Class.forName("zombie.iso.IsoWorld").getField("instance").get(null);
        if(world!=null&&field(world.getClass(),"currentCell").get(world)!=null)throw new AssertionError("native upgrade loaded world cell");
        System.out.println("INTEGRATION_NATIVE_PROFILE game_started=false world_loaded=false world_cell_created=false singleton_initialized="+(world!=null));
    }
}
