import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Complete native module/model registration; never starts a game, world or GL. */
public final class model_registration_Probe {
    static int checks;
    static final String MODEL="SuQingFreshnessLunchbox_Attached";
    static final String MESH="WorldItems/SuQingFreshnessLunchbox/SuQingFreshnessLunchbox_Ground";
    static void check(boolean value,String label){checks++;if(!value)throw new AssertionError(label);}
    static Field field(Class<?> type,String name)throws Exception{
        for(Class<?> c=type;c!=null;c=c.getSuperclass())try{Field f=c.getDeclaredField(name);f.setAccessible(true);return f;}catch(NoSuchFieldException ignored){}
        throw new NoSuchFieldException(name);
    }
    public static void main(String[]args)throws Exception{
        Path input=Paths.get(args[0]);boolean registered="registered".equals(args[2]);
        Class<?> fsType=Class.forName("zombie.ZomboidFileSystem");Object fs=fsType.getField("instance").get(null);
        fsType.getMethod("setCacheDir",String.class).invoke(fs,args[1]);
        @SuppressWarnings("unchecked") ThreadLocal<Boolean> raw=(ThreadLocal<Boolean>)field(fsType,"ignoreActiveFileMap").get(fs);
        raw.set(Boolean.TRUE); // Absolute files; this standalone probe has no vanilla VFS.
        Class<?> managerType=Class.forName("zombie.scripting.ScriptManager");Object manager=managerType.getField("instance").get(null);
        field(managerType,"currentLoadFileMod").set(null,"SuQingFreshnessLunchbox");
        field(managerType,"currentLoadFileAbsPath").set(null,input.toString());
        field(managerType,"currentLoadFileName").set(null,input.getFileName().toString());
        managerType.getField("currentFileName").set(manager,input.toString());
        Class<?> modeType=Class.forName("zombie.scripting.ScriptLoadMode");Object mode=modeType.getField("Init").get(null);
        Class<?> parser=Class.forName("zombie.scripting.ScriptParser");
        String fullFile=new String(Files.readAllBytes(input),StandardCharsets.UTF_8);
        check(fullFile.contains("module Base"),"complete Base module input");
        if(!registered)check(fullFile.contains("// Dedicated attached view;"),"frozen rc.6 line-comment regression fixture");
        // Match LoadFile's preprocessing and the real two-stage module pipeline.
        // Do not slice from 'model': that would hide a malformed preceding token.
        String stripped=(String)parser.getMethod("stripComments",String.class).invoke(null,fullFile);
        managerType.getMethod("ParseScript",modeType,String.class).invoke(manager,mode,stripped);
        Map<?,?> modules=(Map<?,?>)managerType.getField("moduleMap").get(manager);
        Object base=modules.get("Base");check(base!=null,"Base module discovered");
        Object bucket=base.getClass().getField("models").get(base);
        bucket.getClass().getMethod("LoadScripts",modeType).invoke(bucket,mode);
        check(!field(bucket.getClass(),"hasLoadErrors").getBoolean(bucket),"model bucket load has no thrown parser errors");
        Object canonical=null;
        for(String name:new String[]{MODEL,"Base."+MODEL,"base."+MODEL}){
            Object model=managerType.getMethod("getModelScript",String.class).invoke(manager,name);
            check((model!=null)==registered,"native lookup "+name);
            if(model==null)continue;
            Class<?> mt=model.getClass();
            if(canonical==null)canonical=model;else check(model==canonical,"same registered object for "+name);
            check(("Base."+MODEL).equals(mt.getMethod("getScriptObjectFullType").invoke(model)),"qualified model identity");
            check(MESH.equals(mt.getMethod("getMeshName").invoke(model)),"lookup resolves actual FBX mesh");
            check("Clothes/Bag/SuQingFreshnessLunchbox".equals(mt.getMethod("getTextureName").invoke(model)),"lookup resolves retained texture");
            check(Math.abs(mt.getField("scale").getFloat(model)-.4f)<.000001f,"lookup retains model scale");
            check(((Integer)mt.getMethod("getAttachmentCount").invoke(model))==3,"exactly three bottom anchors");
            for(String anchor:new String[]{"bedroll_bottom","bedroll_bottom_big","bedroll_bottom_alice"})
                check(mt.getMethod("getAttachmentById",String.class).invoke(model,anchor)!=null,"registered anchor "+anchor);
        }
        // The item belongs to its own module. Resolve its raw StaticModel string
        // through the same native resolver used by Item.resolveModelScripts.
        managerType.getMethod("ParseScript",modeType,String.class).invoke(manager,mode,"module SuQingFreshnessLunchbox { }");
        Object itemModule=modules.get("SuQingFreshnessLunchbox");
        String resolved=(String)managerType.getMethod("resolveModelScript",Class.forName("zombie.scripting.objects.ScriptModule"),String.class).invoke(manager,itemModule,MODEL);
        Object fromItem=managerType.getMethod("getModelScript",String.class).invoke(manager,resolved);
        check((fromItem!=null)==registered,"item-side resolveModelScript lookup");
        if(registered)check(fromItem==canonical,"item-side lookup is registered model");
        check(managerType.getMethod("getModelScript",String.class).invoke(manager,MODEL.toLowerCase(Locale.ENGLISH))==null,"case-mismatched model rejected");
        System.out.println("MODEL_REGISTRATION_RESULT {\"status\":\"PASS\",\"expected_registered\":"+registered+",\"checks\":"+checks+",\"game_started\":false,\"world_created\":false,\"gl_context\":false}");
    }
}
