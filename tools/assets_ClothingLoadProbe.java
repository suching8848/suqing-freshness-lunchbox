import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Actual OutfitManager + asynchronous XML AssetManager, without client/world/GL. */
public class assets_ClothingLoadProbe {
    static int assertions;
    static void check(boolean value, String why) {
        assertions++;
        if (!value) throw new AssertionError(why);
    }
    static Field field(Class<?> type, String name) throws Exception {
        for (Class<?> c=type;c!=null;c=c.getSuperclass()) {
            try { Field f=c.getDeclaredField(name);f.setAccessible(true);return f; }
            catch (NoSuchFieldException ignored) { }
        }
        throw new NoSuchFieldException(name);
    }
    @SuppressWarnings("unchecked")
    static void register(Object manager, Object module, Object item) throws Exception {
        Class<?> mc=module.getClass();
        ((Map<String,Object>)field(manager.getClass(),"moduleMap").get(manager)).put("SuQingFreshnessLunchbox",module);
        Object collection=field(manager.getClass(),"items").get(manager);
        collection.getClass().getMethod("registerModule",mc).invoke(collection,module);
        Object bucket=mc.getField("items").get(module);
        ((Map<String,Object>)field(bucket.getClass(),"scriptMap").get(bucket)).put("FreshnessLunchbox",item);
        ((List<Object>)field(bucket.getClass(),"scriptList").get(bucket)).add(item);
        ((Map<String,Object>)field(collection.getClass(),"fullTypeToScriptMap").get(collection)).put("SuQingFreshnessLunchbox.FreshnessLunchbox",item);
        ((List<?>)field(collection.getClass(),"allScripts").get(collection)).clear();
    }
    @SuppressWarnings("unchecked")
    static void run(String[] args) throws Exception {
        Path game=Paths.get(args[0]), media=Paths.get(args[1]);
        Class<?> fsClass=Class.forName("zombie.ZomboidFileSystem");
        Object zfs=fsClass.getField("instance").get(null);
        Object base=fsClass.getField("base").get(zfs);
        base.getClass().getMethod("set",java.io.File.class).invoke(base,game.toFile());
        Class<?> tableClass=Class.forName("zombie.FileGuidTable");
        field(fsClass,"fileGuidTable").set(zfs,tableClass.getConstructor().newInstance());
        Method parse=Class.forName("zombie.util.PZXmlUtil").getMethod("parse",Class.class,String.class);
        Object table=parse.invoke(null,tableClass,game.resolve("media/fileGuidTable.xml").toString());
        tableClass.getMethod("setModID",String.class).invoke(table,"game");
        tableClass.getMethod("loaded").invoke(table);
        field(fsClass,"fileGuidTable").set(zfs,table);

        Class<?> smClass=Class.forName("zombie.scripting.ScriptManager"), moduleClass=Class.forName("zombie.scripting.objects.ScriptModule");
        field(smClass,"currentLoadFileMod").set(null,"SuQingFreshnessLunchbox");
        field(smClass,"currentLoadFileAbsPath").set(null,media.resolve("scripts/items_FreshnessLunchbox.txt").toString());
        field(smClass,"currentLoadFileName").set(null,"items_FreshnessLunchbox.txt");
        Object manager=smClass.getField("instance").get(null);
        Object module=moduleClass.getConstructor().newInstance();moduleClass.getField("name").set(module,"SuQingFreshnessLunchbox");
        Class<?> itemClass=Class.forName("zombie.scripting.objects.Item");
        Object item=itemClass.getConstructor().newInstance();itemClass.getMethod("setModule",moduleClass).invoke(item,module);
        String text=new String(Files.readAllBytes(media.resolve("scripts/items_FreshnessLunchbox.txt")),StandardCharsets.UTF_8);
        text=text.substring(text.indexOf("    item "),text.lastIndexOf('}')).replaceAll("(?m)^[ \\t]*Icon[ \\t]*=.*$","");
        // Icon allocation requires OpenGL; its unchanged name/PNG is checked by
        // Python. Every hand-replacement field uses the real Item.Load parser.
        itemClass.getMethod("Load",String.class,String.class).invoke(item,"FreshnessLunchbox",text);
        register(manager,module,item);
        Object right=itemClass.getField("replacePrimaryHand").get(item),left=itemClass.getField("replaceSecondHand").get(item);
        check(right!=null&&left!=null,"native replacement descriptors parsed");
        Class<?> replacement=right.getClass();
        Class<?> outfitClass=Class.forName("zombie.core.skinnedmodel.population.OutfitManager");
        Object outfit=outfitClass.getConstructor().newInstance();outfitClass.getField("instance").set(null,outfit);
        outfitClass.getMethod("loadAllClothingItems").invoke(outfit);
        check(replacement.getField("clothingItem").get(right)==null&&replacement.getField("clothingItem").get(left)==null,
              "rc3 failure reproduced: both replacement assets remain null without mod GUID table");
        System.out.println("NATIVE_CLOTHING_BEFORE missing_guid_table both_assets_null=true PASS");

        Object modTable=parse.invoke(null,tableClass,media.resolve("fileGuidTable.xml").toString());
        tableClass.getMethod("setModID",String.class).invoke(modTable,"SuQingFreshnessLunchbox");
        tableClass.getMethod("mergeFrom",tableClass).invoke(table,modTable);tableClass.getMethod("loaded").invoke(table);
        Map<String,String> active=(Map<String,String>)field(fsClass,"activeFileMap").get(zfs);
        for(String hand:new String[]{"RHand","LHand"}) {
            String path="media/clothing/clothingItems/SuQingFreshnessLunchbox_"+hand+".xml";
            String guid=(String)fsClass.getMethod("getGuidFromFilePath",String.class).invoke(zfs,path);
            check(guid!=null&&guid.startsWith("SuQingFreshnessLunchbox-"),hand+" real merged GUID lookup");
            active.put(path.toLowerCase(Locale.ENGLISH),media.resolve(path.substring(6)).toAbsolutePath().toString());
        }
        Class<?> fsBase=Class.forName("zombie.fileSystem.FileSystem");
        Object fs=Class.forName("zombie.fileSystem.FileSystemImpl").getConstructor().newInstance();
        Class<?> ownersClass=Class.forName("zombie.asset.AssetManagers");Object owners=ownersClass.getConstructor(fsBase).newInstance(fs);
        Class<?> clothingClass=Class.forName("zombie.core.skinnedmodel.population.ClothingItem");
        Class<?> assetManagerClass=Class.forName("zombie.core.skinnedmodel.population.ClothingItemAssetManager");
        Object assetManager=assetManagerClass.getField("instance").get(null);
        assetManagerClass.getMethod("create",Class.forName("zombie.asset.AssetType"),ownersClass).invoke(assetManager,clothingClass.getField("ASSET_TYPE").get(null),owners);
        outfitClass.getMethod("loadAllClothingItems").invoke(outfit);
        Object[] assets={replacement.getField("clothingItem").get(right),replacement.getField("clothingItem").get(left)};
        check(assets[0]!=null&&assets[1]!=null,"both native asynchronous assets allocated from GUID lookup");
        long limit=System.nanoTime()+15_000_000_000L;
        while(System.nanoTime()<limit) {
            fsBase.getMethod("updateAsyncTransactions").invoke(fs);
            boolean ready=true;for(Object asset:assets)ready&=(Boolean)asset.getClass().getMethod("isReady").invoke(asset);
            if(ready)break;
            Thread.sleep(10);
        }
        int index=0;
        for(String hand:new String[]{"RHand","LHand"}) {
            Object asset=assets[index++];
            check((Boolean)clothingClass.getMethod("isReady").invoke(asset),hand+" actual ClothingItemAssetManager reaches READY");
            String expected="media/models_X/Skinned/BackPacks/SuQingFreshnessLunchbox_"+hand+".x";
            check(expected.equals(clothingClass.getField("maleModel").get(asset)),hand+" male model normalized by native asset loader");
            check(expected.equals(clothingClass.getField("femaleModel").get(asset)),hand+" female model normalized by native asset loader");
            check(Boolean.FALSE.equals(clothingClass.getField("isStatic").get(asset)),hand+" skinned asset flag retained");
            check(((List<?>)clothingClass.getField("textureChoices").get(asset)).equals(Collections.singletonList("Clothes/Bag/SuQingFreshnessLunchbox")),hand+" actual texture selection loaded");
            System.out.println("NATIVE_CLOTHING_AFTER "+hand+" state=READY model="+expected+" PASS");
        }
        System.out.println("NATIVE_CLOTHING_SUMMARY assertions="+assertions+" failures=0 game_started=false world_created=false gl_context=false async_asset_loader=true");
    }
    public static void main(String[] args) throws Exception {
        try {run(args);System.exit(0);} catch(Throwable e) {e.printStackTrace();System.exit(1);}
    }
}
