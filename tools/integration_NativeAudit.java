import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.function.Function;

/** Native parsers and option readers only. Never creates a world or game state. */
public final class integration_NativeAudit {
    static int checks;
    static void check(boolean value,String label) { checks++;if(!value)throw new AssertionError(label); }
    static Field field(Class<?> type,String name)throws Exception{
        for(Class<?> c=type;c!=null;c=c.getSuperclass())try{Field f=c.getDeclaredField(name);f.setAccessible(true);return f;}catch(NoSuchFieldException ignored){}
        throw new NoSuchFieldException(name);
    }
    static Object parse(Path path)throws Exception{
        Class<?> parser=Class.forName("zombie.scripting.ScriptParser");
        String text=new String(Files.readAllBytes(path),StandardCharsets.UTF_8);
        text=(String)parser.getMethod("stripComments",String.class).invoke(null,text);
        return parser.getMethod("parse",String.class).invoke(null,text);
    }
    static Object first(Object block)throws Exception{return ((List<?>)block.getClass().getField("children").get(block)).get(0);}
    static String value(Object block,String name)throws Exception{
        Object v=block.getClass().getMethod("getValue",String.class).invoke(block,name);
        return v==null?null:v.getClass().getMethod("getValue").invoke(v).toString().trim();
    }
    @SuppressWarnings("unchecked")
    static void registerItem(Object manager,Object module,Object script)throws Exception{
        String moduleName=module.getClass().getField("name").get(module).toString();
        ((Map<String,Object>)field(manager.getClass(),"moduleMap").get(manager)).put(moduleName,module);
        Object collection=field(manager.getClass(),"items").get(manager);
        Class<?> cc=Class.forName("zombie.scripting.ScriptBucketCollection");
        cc.getMethod("registerModule",module.getClass()).invoke(collection,module);
        Object bucket=module.getClass().getField("items").get(module);
        String full=script.getClass().getMethod("getFullName").invoke(script).toString();
        ((Map<String,Object>)field(bucket.getClass(),"scriptMap").get(bucket)).put(full.substring(full.indexOf('.')+1),script);
        List<Object> list=(List<Object>)field(bucket.getClass(),"scriptList").get(bucket);if(!list.contains(script))list.add(script);
        ((Map<String,Object>)field(collection.getClass(),"fullTypeToScriptMap").get(collection)).put(full,script);
        ((List<?>)field(collection.getClass(),"allScripts").get(collection)).clear();
    }
    @SuppressWarnings("unchecked")
    static void removeItem(Object manager,Object module,Object script)throws Exception{
        Object collection=field(manager.getClass(),"items").get(manager);
        Object bucket=module.getClass().getField("items").get(module);
        String full=script.getClass().getMethod("getFullName").invoke(script).toString();
        ((Map<String,Object>)field(bucket.getClass(),"scriptMap").get(bucket)).remove(full.substring(full.indexOf('.')+1));
        ((List<?>)field(bucket.getClass(),"scriptList").get(bucket)).remove(script);
        ((Map<String,Object>)field(collection.getClass(),"fullTypeToScriptMap").get(collection)).remove(full);
        ((List<?>)field(collection.getClass(),"allScripts").get(collection)).clear();
    }
    public static void main(String[]args)throws Exception{
        Path main=Paths.get(args[0]), ordinary=Paths.get(args[1]);
        Class<?> manager=Class.forName("zombie.scripting.ScriptManager");
        field(manager,"currentLoadFileMod").set(null,"SuQingFreshnessLunchbox");
        field(manager,"currentLoadFileAbsPath").set(null,main.resolve("media/scripts/items_FreshnessLunchbox.txt").toString());
        field(manager,"currentLoadFileName").set(null,"items_FreshnessLunchbox.txt");
        Object root=parse(main.resolve("media/scripts/items_FreshnessLunchbox.txt"));
        Object moduleBlock=first(root), itemBlock=first(moduleBlock);
        Class<?> block=root.getClass();
        check("SuQingFreshnessLunchbox".equals(block.getField("id").get(moduleBlock)),"independent module");
        check("FreshnessLunchbox".equals(block.getField("id").get(itemBlock)),"stable item name");
        check("SuQingFreshnessLunchbox".equals(value(itemBlock,"Icon")),"dedicated item icon reference");
        check("SuQingFreshnessLunchbox.AcceptFood".equals(value(itemBlock,"AcceptItemFunction")),"native food filter hook");
        check("SuQingFreshnessLunchbox_RHand holdingbagright".equals(value(itemBlock,"ReplaceInPrimaryHand")),"right-hand model");
        check("SuQingFreshnessLunchbox_LHand holdingbagleft".equals(value(itemBlock,"ReplaceInSecondHand")),"left-hand model");
        check(value(itemBlock,"CanBeEquipped")==null && value(itemBlock,"BodyLocation")==null,"no fake wearable slot");
        // Icon resolution requests GL resources; its exact reference and file are
        // checked separately. Omit only that field from the headless Item.Load.
        Object icon=block.getMethod("getValue",String.class).invoke(itemBlock,"Icon");
        ((List<?>)block.getField("values").get(itemBlock)).remove(icon);
        ((List<?>)block.getField("elements").get(itemBlock)).remove(icon);
        StringBuilder text=new StringBuilder();block.getMethod("prettyPrint",int.class,StringBuilder.class).invoke(itemBlock,0,text);
        Class<?> moduleClass=Class.forName("zombie.scripting.objects.ScriptModule");
        Object module=moduleClass.getConstructor().newInstance();moduleClass.getField("name").set(module,"SuQingFreshnessLunchbox");
        Class<?> itemClass=Class.forName("zombie.scripting.objects.Item");
        Object item=itemClass.getConstructor().newInstance();itemClass.getMethod("setModule",moduleClass).invoke(item,module);
        itemClass.getMethod("Load",String.class,String.class).invoke(item,"FreshnessLunchbox",text.toString());
        Class<?> itemType=Class.forName("zombie.scripting.objects.ItemType");
        check((Boolean)itemClass.getMethod("isItemType",itemType).invoke(item,itemType.getField("CONTAINER").get(null)),"real native container type");
        check(((Integer)itemClass.getField("capacity").get(item))==4,"vanilla starting capacity 4");
        check(((Integer)itemClass.getField("weightReduction").get(item))==50,"vanilla starting reduction 50");
        check(((Float)itemClass.getMethod("getActualWeight").invoke(item))==1f,"vanilla weight 1");
        check(((Float)itemClass.getMethod("getMaxItemSize").invoke(item))==1f,"vanilla maximum item size");
        Object recipesModule=first(parse(main.resolve("media/scripts/recipes_FreshnessLunchbox.txt")));
        List<?> recipeBlocks=(List<?>)block.getField("children").get(recipesModule);
        check(recipeBlocks.size()==2,"two independent native crafting routes");
        Class<?> recipeClass=Class.forName("zombie.scripting.entity.components.crafting.CraftRecipe");
        Class<?> inputClass=Class.forName("zombie.scripting.entity.components.crafting.InputScript");
        for(int route=0;route<2;route++){
        Object recipeBlock=recipeBlocks.get(route);
        String name=route==0?"MakeFreshnessLunchboxFromLunchbox":"MakeFreshnessLunchboxFromMetal";
        Object recipe=recipeClass.getConstructor().newInstance();recipeClass.getMethod("setModule",moduleClass).invoke(recipe,module);
        check(name.equals(block.getField("id").get(recipeBlock)),"stable route ID "+route);
        field(recipeClass,"scriptObjectName").set(recipe,name);
        recipeClass.getMethod("Load",String.class,block).invoke(recipe,name,recipeBlock);
        List<?> inputs=(List<?>)recipeClass.getMethod("getInputs").invoke(recipe);
        check(inputs.size()==6,"source or metal, digital, pocket, classic, wire and tool rows");
        int[] counts={route==0?1:2,1,1,1,2};
        for(int i=0;i<5;i++){
            check((Boolean)inputClass.getMethod("isDestroy").invoke(inputs.get(i)),"native material destruction "+i);
            check((Boolean)inputClass.getMethod("isItemCount").invoke(inputs.get(i)),"physical item counting "+i);
            check(((Float)inputClass.getMethod("getAmount").invoke(inputs.get(i)))==counts[i],"correct material count "+i);
        }
        List<?> bases=(List<?>)inputClass.getMethod("getItems").invoke(inputs.get(0));
        if(route==0){
            check((Boolean)inputClass.getMethod("isEmptyContainer").invoke(inputs.get(0)),"source box must be empty");
            check(bases.size()==2,"two vanilla lunchbox variants");
        }else{
            check(!(Boolean)inputClass.getMethod("isEmptyContainer").invoke(inputs.get(0)),"metal route has no source-box restriction");
            check(bases.size()==1&&bases.get(0).toString().equals("Base.SmallSheetMetal"),"two small metal sheets route");
        }
        Set<?> watches=new HashSet<Object>((List<?>)inputClass.getMethod("getItems").invoke(inputs.get(1)));
        check(watches.size()==6,"six digital watch variants");
        for(Object watch:watches)check(watch.toString().contains("_Digital"),"digital watch family");
        List<?> pocket=(List<?>)inputClass.getMethod("getItems").invoke(inputs.get(2));
        check(pocket.size()==1&&pocket.get(0).toString().equals("Base.Pocketwatch"),"one actual pocketwatch");
        Set<?> classics=new HashSet<Object>((List<?>)inputClass.getMethod("getItems").invoke(inputs.get(3)));
        check(classics.size()==8,"eight classic watch variants");
        for(Object watch:classics)check(watch.toString().contains("_Classic")&&!watches.contains(watch),"disjoint classic family");
        List<?> wires=(List<?>)inputClass.getMethod("getItems").invoke(inputs.get(4));
        check(wires.size()==1&&wires.get(0).toString().equals("Base.ElectricWire"),"two physical wires");
        check((Boolean)inputClass.getMethod("isKeep").invoke(inputs.get(5)),"screwdriver retained");
        check(((Integer)recipeClass.getMethod("getRequiredSkillCount").invoke(recipe))==0,"no extra skill gate");
        check(((Integer)recipeClass.getMethod("getOutputCount").invoke(recipe))==1,"one native output");
        check("SuQingFreshnessLunchbox".equals(recipeClass.getMethod("getCategory").invoke(recipe)),"dedicated native crafting category");
        check("SuQingFreshnessLunchbox.Crafting.TestItem".equals(value(recipeBlock,"OnTest")),"input predicate");
        check("SuQingFreshnessLunchbox.Crafting.OnCreate".equals(value(recipeBlock,"OnCreate")),"native creation callback");
        }
        Class<?> doubleOption=Class.forName("zombie.config.DoubleConfigOption");
        Object hours=doubleOption.getConstructor(String.class,double.class,double.class,double.class).newInstance("RestoreHours",0.25,1000.0,10.0);
        doubleOption.getMethod("parse",String.class).invoke(hours,"0.25");
        check(((Double)doubleOption.getMethod("getValue").invoke(hours))==0.25,"native lower-bound time option");
        Class<?> translator=Class.forName("zombie.core.Translator"), language=Class.forName("zombie.core.Language");
        Constructor<?> languageCtor=language.getDeclaredConstructor(String.class,String.class,String.class,boolean.class);languageCtor.setAccessible(true);
        Method fill=translator.getDeclaredMethod("tryFillMapFromFile",String.class,String.class,Map.class,language,Function.class);fill.setAccessible(true);
        for(String lang:Arrays.asList("CN","CH","EN")){
            Object locale=languageCtor.newInstance(lang,lang,"EN",false);
            for(String category:Arrays.asList("Mod","IG_UI","ItemName","Recipes","Tooltip","Sandbox")){
                Map<String,String> values=new LinkedHashMap<String,String>();
                fill.invoke(null,main.toString(),category,values,locale,Function.identity());
                check(!values.isEmpty(),"native translation reader "+lang+"/"+category);
                if(category.equals("ItemName"))check((lang.equals("EN")?"SuQing's Freshness Lunchbox":"蘇清的返鲜餐盒").equals(values.get("SuQingFreshnessLunchbox.FreshnessLunchbox")),"localized item name "+lang);
                if(category.equals("Recipes"))check(values.containsKey("MakeFreshnessLunchboxFromLunchbox")&&values.containsKey("MakeFreshnessLunchboxFromMetal"),"both localized recipe routes "+lang);
            }
        }
        Object ordinaryModule=moduleClass.getConstructor().newInstance();moduleClass.getField("name").set(ordinaryModule,"SuQingContainerUpgrade");
        Object upgradeModuleBlock=first(parse(ordinary.resolve("media/scripts/SuQingContainerUpgrade.txt")));
        List<?> upgradeRecipes=(List<?>)block.getField("children").get(upgradeModuleBlock);
        check(upgradeRecipes.size()==6,"ordinary upgrade native five tiers and restoration");
        for(int tier=0;tier<6;tier++){
            Object recipeBlock=upgradeRecipes.get(tier);
            String name=tier==5?"SuQingRestore":"SuQingUpgrade"+(tier+1);
            check(name.equals(block.getField("id").get(recipeBlock)),"ordinary recipe identity "+name);
            Object recipe=recipeClass.getConstructor().newInstance();recipeClass.getMethod("setModule",moduleClass).invoke(recipe,ordinaryModule);
            field(recipeClass,"scriptObjectName").set(recipe,name);recipeClass.getMethod("Load",String.class,block).invoke(recipe,name,recipeBlock);
            List<?> inputs=(List<?>)recipeClass.getMethod("getInputs").invoke(recipe);Object kept=inputs.get(0);
            check((Boolean)inputClass.getMethod("isKeep").invoke(kept),"same native item remains kept "+name);
            List<?> ids=(List<?>)inputClass.getMethod("getItems").invoke(kept);
            check(Collections.frequency(ids,"SuQingFreshnessLunchbox.FreshnessLunchbox")==1,"built-in lunchbox input once "+name);
            check(Collections.frequency(ids,"Base.Bag_Schoolbag")==1,"ordinary vanilla input preserved "+name);
            check(value(recipeBlock,"OnCreate").equals(tier==5?"SuQingContainerUpgrade.Restore":"SuQingContainerUpgrade.Create"+(tier+1)),"existing native callbacks preserved "+name);
        }
        Object scriptManager=manager.getField("instance").get(null);
        Object baseModule=moduleClass.getConstructor().newInstance();moduleClass.getField("name").set(baseModule,"Base");
        Object schoolbag=itemClass.getConstructor().newInstance();itemClass.getMethod("setModule",moduleClass).invoke(schoolbag,baseModule);
        itemClass.getMethod("Load",String.class,String.class).invoke(schoolbag,"Bag_Schoolbag","item Bag_Schoolbag { ItemType = Container, Weight = 1, Capacity = 4, WeightReduction = 50, }");
        registerItem(scriptManager,baseModule,schoolbag);
        for(String fixture:Arrays.asList("Needle","RippedSheets","LeatherStrips","Thread")){
            Object material=itemClass.getConstructor().newInstance();itemClass.getMethod("setModule",moduleClass).invoke(material,baseModule);
            String extra=fixture.equals("Needle")?"Tags = base:sewingneedle, ":"";
            itemClass.getMethod("Load",String.class,String.class).invoke(material,fixture,"item "+fixture+" { ItemType = Normal, Weight = 0.1, "+extra+"}");
            registerItem(scriptManager,baseModule,material);
        }
        Class.forName("zombie.inventory.ItemTags").getMethod("Init",ArrayList.class).invoke(null,manager.getMethod("getAllItems").invoke(scriptManager));
        Method resolve=inputClass.getDeclaredMethod("OnPostWorldDictionaryInit");resolve.setAccessible(true);
        List<List<?>> absentMaterialCaches=new ArrayList<List<?>>();
        for(String scenario:Arrays.asList("provider_absent","provider_before_recipes","provider_after_recipes")){
            if(!scenario.equals("provider_absent")) registerItem(scriptManager,module,item);
            if(scenario.equals("provider_after_recipes")) removeItem(scriptManager,module,item);
            List<Object> keptInputs=new ArrayList<Object>();
            List<List<?>> allInputs=new ArrayList<List<?>>();
            for(int tier=0;tier<6;tier++){
                String name=tier==5?"SuQingRestore":"SuQingUpgrade"+(tier+1);
                Object recipe=recipeClass.getConstructor().newInstance();recipeClass.getMethod("setModule",moduleClass).invoke(recipe,ordinaryModule);
                field(recipeClass,"scriptObjectName").set(recipe,name);recipeClass.getMethod("Load",String.class,block).invoke(recipe,name,upgradeRecipes.get(tier));
                List<?> inputs=(List<?>)recipeClass.getMethod("getInputs").invoke(recipe);keptInputs.add(inputs.get(0));allInputs.add(inputs);
                check(((List<?>)inputClass.getMethod("getPossibleInputItems").invoke(inputs.get(0))).isEmpty(),"cache is deferred until native post-dictionary stage "+scenario+"/"+name);
            }
            if(scenario.equals("provider_after_recipes")) registerItem(scriptManager,module,item);
            int materialIndex=0;
            for(int tier=0;tier<6;tier++){
                Object kept=keptInputs.get(tier);resolve.invoke(kept);
                List<?> possible=(List<?>)inputClass.getMethod("getPossibleInputItems").invoke(kept);
                check(Collections.frequency(possible,schoolbag)==1,"existing native schoolbag cache unaffected "+scenario+"/"+tier);
                check(Collections.frequency(possible,item)==(scenario.equals("provider_absent")?0:1),"optional provider native cache resolves once "+scenario+"/"+tier);
                check(((List<?>)inputClass.getMethod("getItems").invoke(kept)).contains("SuQingFreshnessLunchbox.FreshnessLunchbox"),"unresolved optional identity retained "+scenario+"/"+tier);
                List<?> inputs=allInputs.get(tier);
                for(int i=1;i<inputs.size();i++){
                    Object input=inputs.get(i);resolve.invoke(input);List<?> cache=(List<?>)inputClass.getMethod("getPossibleInputItems").invoke(input);
                    check(cache.size()==1,"existing material or needle native cache still resolves "+scenario+"/"+tier+"/"+i);
                    if(scenario.equals("provider_absent")) absentMaterialCaches.add(new ArrayList<Object>(cache));
                    else check(cache.equals(absentMaterialCaches.get(materialIndex)),"optional provider cannot change material native cache "+scenario+"/"+tier+"/"+i);
                    materialIndex++;
                }
            }
            if(!scenario.equals("provider_absent")) removeItem(scriptManager,module,item);
        }
        System.out.println("INTEGRATION_NATIVE assertions="+checks+" failures=0 game_started=false world_created=false");
    }
}
