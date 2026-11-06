import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Script/model metadata only: no world, character, rendering or OpenGL. */
public final class AttachmentAssetProbe {
    static int assertions;
    static void check(boolean ok, String detail) {
        assertions++;
        if (!ok) throw new AssertionError(detail);
    }
    static Object parse(Path path) throws Exception {
        Class<?> parser = Class.forName("zombie.scripting.ScriptParser");
        String text = new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
        text = (String)parser.getMethod("stripComments", String.class).invoke(null, text);
        return parser.getMethod("parse", String.class).invoke(null, text);
    }
    static Object first(Object block) throws Exception {
        return ((List<?>)block.getClass().getField("children").get(block)).get(0);
    }
    static String text(Object block) throws Exception {
        StringBuilder out = new StringBuilder();
        block.getClass().getMethod("prettyPrint", int.class, StringBuilder.class).invoke(block, 0, out);
        return out.toString();
    }
    static String value(Object block, String key) throws Exception {
        Object value = block.getClass().getMethod("getValue", String.class).invoke(block, key);
        return value == null ? null : value.getClass().getMethod("getValue").invoke(value).toString().trim();
    }
    public static void main(String[] args) throws Exception {
        Path media = Paths.get(args[0]);
        Object modelBlock = first(first(parse(media.resolve("scripts/models_FreshnessLunchbox_Attached.txt"))));
        Class<?> modelType = Class.forName("zombie.scripting.objects.ModelScript");
        Object model = modelType.getConstructor().newInstance();
        modelType.getMethod("Load", String.class, String.class).invoke(model,
            "SuQingFreshnessLunchbox_Attached", text(modelBlock));
        check("WorldItems/SuQingFreshnessLunchbox/SuQingFreshnessLunchbox_Ground".equals(
            modelType.getField("meshName").get(model)), "Independent mesh reference");
        check("Clothes/Bag/SuQingFreshnessLunchbox".equals(modelType.getField("textureName").get(model)),
            "Existing material reference");
        check(Math.abs(modelType.getField("scale").getFloat(model) - 0.4f) < 0.000001f, "Native ground mesh scale");
        check((Integer)modelType.getMethod("getAttachmentCount").invoke(model) == 3, "Exactly three bottom anchors");
        for (String id : Arrays.asList("bedroll_bottom", "bedroll_bottom_big", "bedroll_bottom_alice")) {
            Object attachment = modelType.getMethod("getAttachmentById", String.class).invoke(model, id);
            check(attachment != null, "Native anchor parsed: " + id);
            for (String getter : Arrays.asList("getOffset", "getRotate")) {
                Object vector = attachment.getClass().getMethod(getter).invoke(attachment);
                for (String axis : Arrays.asList("x", "y", "z"))
                    check(Float.isFinite(vector.getClass().getField(axis).getFloat(vector)), "Finite " + id + "/" + getter);
            }
            check((Float)attachment.getClass().getMethod("getScale").invoke(attachment) == 1f, "No extra anchor scaling");
        }
        Object itemBlock = first(first(parse(media.resolve("scripts/items_FreshnessLunchbox.txt"))));
        check("SuQingFreshnessLunchbox".equals(value(itemBlock, "AttachmentType")), "Dedicated attachment type declared");
        check("SuQingFreshnessLunchbox_Attached".equals(value(itemBlock, "StaticModel")), "Dedicated attached view declared");
        check(value(itemBlock, "CanBeEquipped") == null && value(itemBlock, "BodyLocation") == null, "No artificial wearable slot");
        // Item.Load may request icon GL data; strip only Icon, which existing asset QA covers.
        Class<?> blockType = itemBlock.getClass();
        Object icon = blockType.getMethod("getValue", String.class).invoke(itemBlock, "Icon");
        ((List<?>)blockType.getField("values").get(itemBlock)).remove(icon);
        ((List<?>)blockType.getField("elements").get(itemBlock)).remove(icon);
        Class<?> moduleType = Class.forName("zombie.scripting.objects.ScriptModule");
        Object module = moduleType.getConstructor().newInstance();
        moduleType.getField("name").set(module, "SuQingFreshnessLunchbox");
        Class<?> itemType = Class.forName("zombie.scripting.objects.Item");
        Object item = itemType.getConstructor().newInstance();
        itemType.getMethod("setModule", moduleType).invoke(item, module);
        itemType.getMethod("Load", String.class, String.class).invoke(item, "FreshnessLunchbox", text(itemBlock));
        check("SuQingFreshnessLunchbox".equals(itemType.getField("attachmentType").get(item)), "Native Item.Load attachment type");
        check("SuQingFreshnessLunchbox_Attached".equals(itemType.getMethod("getStaticModel").invoke(item)), "Native Item.Load StaticModel");
        check(itemType.getField("capacity").getInt(item) == 4 && itemType.getField("weightReduction").getInt(item) == 50,
            "Base container stats retained");
        System.out.println("ATTACHMENT_ASSET assertions=" + assertions + " failures=0 PASS");
        System.out.println("game_started=false world_created=false character_created=false gl_context=false");
    }
}
