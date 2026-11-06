import java.lang.reflect.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Physical native GUID-table loading and real cross-mod clothing, no world/GL. */
public class assets_CrossModGuidProbe {
    static int assertions;
    static void check(boolean b,String why){assertions++;if(!b)throw new AssertionError(why);}
    static Field field(Class<?> c,String n)throws Exception{return assets_ClothingLoadProbe.field(c,n);}
    static Object zfs;static Class<?> fc,tc;static List<String[]> rows;
    @SuppressWarnings("unchecked")
    static Object load(boolean lunchbox,boolean overlay)throws Exception{
        List<String> mods=(List<String>)field(fc,"mods").get(zfs);mods.clear();
        for(String[] row:rows)if(lunchbox||!row[0].equals("SuQingFreshnessLunchbox"))mods.add(row[0]);
        Map<String,String> active=(Map<String,String>)field(fc,"activeFileMap").get(zfs);
        active.clear();
        if(overlay)for(String[] row:rows)if(row[0].equals("SuQingFreshnessLunchbox"))active.put("media/fileguidtable.xml",Paths.get(row[2],"media/fileGuidTable.xml").toString());
        fc.getMethod("loadFileGuidTable").invoke(zfs);
        return field(fc,"fileGuidTable").get(zfs);
    }
    @SuppressWarnings("unchecked")
    static Map<String,String> mapping(Object table,String name)throws Exception{return new TreeMap<String,String>((Map<String,String>)field(tc,name).get(table));}
    static String lookup(Object table,String path)throws Exception{return(String)tc.getMethod("getGuidFromFilePath",String.class).invoke(table,path);}
    @SuppressWarnings("unchecked")
    static Object headScript(Path path)throws Exception{
        Class<?> sc=Class.forName("zombie.scripting.ScriptManager"),mc=Class.forName("zombie.scripting.objects.ScriptModule"),ic=Class.forName("zombie.scripting.objects.Item");
        field(sc,"currentLoadFileMod").set(null,"FantasyWorkshopVS42_4.0");field(sc,"currentLoadFileAbsPath").set(null,path.toString());field(sc,"currentLoadFileName").set(null,path.getFileName().toString());
        Object parsed=Class.forName("zombie.scripting.ScriptParser").getMethod("parse",String.class).invoke(null,new String(Files.readAllBytes(path),StandardCharsets.UTF_8));
        Class<?> bc=parsed.getClass();Object moduleBlock=((List<?>)bc.getField("children").get(parsed)).get(0),target=null;
        for(Object b:(List<?>)bc.getField("children").get(moduleBlock))if("head01_nan0".equals(bc.getField("id").get(b))){target=b;break;}
        check(target!=null,"actual oldcat head script found");StringBuilder text=new StringBuilder();bc.getMethod("prettyPrint",int.class,StringBuilder.class).invoke(target,0,text);
        String body=text.toString().replaceAll("(?m)^[ \\t]*Icon[ \\t]*=.*$","");
        Object module=mc.getConstructor().newInstance();mc.getField("name").set(module,"Base");Object item=ic.getConstructor().newInstance();ic.getMethod("setModule",mc).invoke(item,module);ic.getMethod("Load",String.class,String.class).invoke(item,"head01_nan0",body);
        Object manager=sc.getField("instance").get(null);((Map<String,Object>)field(sc,"moduleMap").get(manager)).put("Base",module);
        Object collection=field(sc,"items").get(manager);collection.getClass().getMethod("registerModule",mc).invoke(collection,module);Object bucket=mc.getField("items").get(module);
        ((Map<String,Object>)field(bucket.getClass(),"scriptMap").get(bucket)).put("head01_nan0",item);((List<Object>)field(bucket.getClass(),"scriptList").get(bucket)).add(item);
        ((Map<String,Object>)field(collection.getClass(),"fullTypeToScriptMap").get(collection)).put("Base.head01_nan0",item);((List<?>)field(collection.getClass(),"allScripts").get(collection)).clear();return item;
    }
    @SuppressWarnings("unchecked")
    static void run(String[]args)throws Exception{
        Path game=Paths.get(args[0]);rows=new ArrayList<String[]>();for(String line:Files.readAllLines(Paths.get(args[1]),StandardCharsets.UTF_8))if(!line.isEmpty())rows.add(line.split("\t",-1));
        fc=Class.forName("zombie.ZomboidFileSystem");zfs=fc.getField("instance").get(null);tc=Class.forName("zombie.FileGuidTable");
        Object base=fc.getField("base").get(zfs);base.getClass().getMethod("set",java.io.File.class).invoke(base,game.toFile());Object work=field(fc,"workdir").get(zfs);work.getClass().getMethod("set",java.io.File.class).invoke(work,game.resolve("media").toFile());
        Class<?> choose=Class.forName("zombie.gameStates.ChooseGameInfo"),modc=Class.forName("zombie.gameStates.ChooseGameInfo$Mod");Map<String,Object> cache=(Map<String,Object>)field(choose,"Mods").get(null);cache.clear();
        Path oldcat=null;
        for(String[]row:rows){Object mod=modc.getConstructor(String.class).newInstance(row[1]);modc.getMethod("setId",String.class).invoke(mod,row[0]);modc.getField("versionDir").set(mod,row[2]);modc.getField("commonDir").set(mod,row[3]);field(modc,"availableDone").setBoolean(mod,true);field(modc,"available").setBoolean(mod,true);cache.put(row[0],mod);if(row[0].equals("FantasyWorkshopVS42_4.0"))oldcat=Paths.get(row[2]);}
        check(oldcat!=null,"actual FantasyWorkshop source supplied");
        String headPath="media/clothing/clothingItems/head01_nan0.xml",stockPath="media/clothing/clothingItems/Bag_Lunchbox_RHand.xml";
        Object before=load(false,false);Map<String,String> oldGuids=mapping(before,"guidToPath"),oldPaths=mapping(before,"pathToGuid");String headGuid=lookup(before,headPath),stockGuid=lookup(before,stockPath);
        check("FantasyWorkshopVS42_4.0-4c9dba1a-209b-4fca-aeb6-24b7b468f848".equals(headGuid),"oldcat head GUID resolved before lunchbox");check(stockGuid!=null,"physical base table loaded");
        for(boolean overlay:new boolean[]{false,true}){
            Object after=load(true,overlay);Map<String,String> newGuids=mapping(after,"guidToPath"),newPaths=mapping(after,"pathToGuid");
            for(Map.Entry<String,String> e:oldGuids.entrySet())check(e.getValue().equals(newGuids.get(e.getKey())),"existing GUID retained "+e.getKey());
            for(Map.Entry<String,String> e:oldPaths.entrySet())check(e.getValue().equals(newPaths.get(e.getKey())),"existing path retained "+e.getKey());
            check(newGuids.size()==oldGuids.size()+2&&newPaths.size()==oldPaths.size()+2,"only two lunchbox mappings added");check(headGuid.equals(lookup(after,headPath)),"head GUID unchanged with virtual overlay="+overlay);check(stockGuid.equals(lookup(after,stockPath)),"stock GUID unchanged with virtual overlay="+overlay);
            check(lookup(after,"media/clothing/clothingItems/SuQingFreshnessLunchbox_RHand.xml")!=null,"lunchbox right GUID loaded");check(lookup(after,"media/clothing/clothingItems/SuQingFreshnessLunchbox_LHand.xml")!=null,"lunchbox left GUID loaded");
            System.out.println("NATIVE_CROSS_GUID overlay="+overlay+" baseline_guids="+oldGuids.size()+" baseline_paths="+oldPaths.size()+" after_guids="+newGuids.size()+" after_paths="+newPaths.size()+" head="+headGuid+" PASS");
        }
        Map<String,String> active=(Map<String,String>)field(fc,"activeFileMap").get(zfs);active.put(headPath.toLowerCase(Locale.ENGLISH),oldcat.resolve(headPath).toString());
        Object item=headScript(oldcat.resolve("media/scripts/koroeMask.txt"));Class<?> oc=Class.forName("zombie.core.skinnedmodel.population.OutfitManager");Object outfit=oc.getConstructor().newInstance();oc.getField("instance").set(null,outfit);
        Class<?> fsc=Class.forName("zombie.fileSystem.FileSystem"),ownersc=Class.forName("zombie.asset.AssetManagers"),cc=Class.forName("zombie.core.skinnedmodel.population.ClothingItem"),amc=Class.forName("zombie.core.skinnedmodel.population.ClothingItemAssetManager");Object fs=Class.forName("zombie.fileSystem.FileSystemImpl").getConstructor().newInstance(),owners=ownersc.getConstructor(fsc).newInstance(fs),am=amc.getField("instance").get(null);amc.getMethod("create",Class.forName("zombie.asset.AssetType"),ownersc).invoke(am,cc.getField("ASSET_TYPE").get(null),owners);
        oc.getMethod("loadAllClothingItems").invoke(outfit);Object asset=item.getClass().getMethod("getClothingItemAsset").invoke(item);check(asset!=null,"real Base.head01_nan0 clothing asset allocated");
        long limit=System.nanoTime()+15_000_000_000L;while(System.nanoTime()<limit){fsc.getMethod("updateAsyncTransactions").invoke(fs);if((Boolean)cc.getMethod("isReady").invoke(asset))break;Thread.sleep(10);}
        check((Boolean)cc.getMethod("isReady").invoke(asset),"oldcat head actual asynchronous XML asset reaches READY");check("head01_nan0".equals(cc.getField("maleModel").get(asset))&&"head01_nan0".equals(cc.getField("femaleModel").get(asset)),"oldcat real model names loaded");
        Class<?> vc=Class.forName("zombie.core.skinnedmodel.visual.ItemVisual");Object visual=vc.getConstructor().newInstance();vc.getMethod("setItemType",String.class).invoke(visual,"Base.head01_nan0");vc.getMethod("setClothingItemName",String.class).invoke(visual,"head01_nan0");check(vc.getMethod("getClothingItem").invoke(visual)==asset,"existing-style visual resolves actual script clothing asset");
        ByteBuffer buffer=ByteBuffer.allocate(4096);vc.getMethod("save",ByteBuffer.class).invoke(visual,buffer);buffer.flip();Object restored=vc.getConstructor().newInstance();vc.getMethod("load",ByteBuffer.class,int.class).invoke(restored,buffer,249);check(vc.getMethod("getClothingItem").invoke(restored)==asset,"real current ItemVisual save/load retains head clothing asset resolution");
        String memo="not_present";try{memo=String.valueOf(Class.forName("pzopt.LookupMemo").getField("ON").getBoolean(null));}catch(ClassNotFoundException ignored){}
        System.out.println("NATIVE_CROSS_HEAD asset=READY models=head01_nan0 visual_save_load=PASS");System.out.println("NATIVE_CROSS_GUID_SUMMARY assertions="+assertions+" failures=0 pzo_lookup_memo="+memo+" game_started=false world_created=false gl_context=false enabled_mod_details_fixture=true");
    }
    public static void main(String[]args)throws Exception{try{run(args);System.exit(0);}catch(Throwable e){e.printStackTrace();System.exit(1);}}
}
