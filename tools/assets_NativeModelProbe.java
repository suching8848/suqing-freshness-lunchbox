import java.lang.reflect.*;
import java.nio.FloatBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Only standalone native Assimp / ModelScript parsers. No game, world or GL. */
public class assets_NativeModelProbe {
    static int assertions;
    static void check(boolean value, String why) {
        assertions++;
        if (!value) throw new AssertionError(why);
    }
    static Object invoke(Object instance, String name, Class<?>[] signature, Object... args) throws Exception {
        return instance.getClass().getMethod(name, signature).invoke(instance, args);
    }
    static void sameBuffer(Object a, Object b, String method, Class<?>[] signature, Object... args) throws Exception {
        FloatBuffer first = ((FloatBuffer) invoke(a, method, signature, args)).duplicate();
        FloatBuffer second = ((FloatBuffer) invoke(b, method, signature, args)).duplicate();
        check(first.remaining() == second.remaining(), method + " component count");
        while (first.hasRemaining()) {
            float x = first.get(), y = second.get();
            check(Float.isFinite(x) && Float.floatToIntBits(x) == Float.floatToIntBits(y), method + " exact native geometry");
        }
    }
    public static void main(String[] args) throws Exception {
        Path game = Paths.get(args[0]), media = Paths.get(args[1]);
        // The installed importer initializer only selects PZ's own jassimp64
        // library loader. It does not initialize a world, renderer or client.
        Class.forName("zombie.core.skinnedmodel.model.jassimp.JAssImpImporter").getMethod("Init").invoke(null);
        Class<?> jassimp = Class.forName("jassimp.Jassimp");
        Method load = jassimp.getMethod("importFile", String.class);
        String[][] pairs = {
            {"media/models_X/Skinned/BackPacks/PlasticLunchBox_RHand.x", "models_X/Skinned/BackPacks/SuQingFreshnessLunchbox_RHand.x"},
            {"media/models_X/Skinned/BackPacks/PlasticLunchBox_LHand.x", "models_X/Skinned/BackPacks/SuQingFreshnessLunchbox_LHand.x"},
            {"media/models_X/WorldItems/Clothing/PlasticLunchBox_Ground.fbx", "models_X/WorldItems/SuQingFreshnessLunchbox/SuQingFreshnessLunchbox_Ground.fbx"}
        };
        for (String[] pair : pairs) {
            Object original = load.invoke(null, game.resolve(pair[0]).toAbsolutePath().toString());
            Object derived = load.invoke(null, media.resolve(pair[1]).toAbsolutePath().toString());
            List<?> first = (List<?>) invoke(original, "getMeshes", new Class<?>[0]);
            List<?> second = (List<?>) invoke(derived, "getMeshes", new Class<?>[0]);
            check(!first.isEmpty() && first.size() == second.size(), "native mesh counts");
            for (int i = 0; i < first.size(); i++) {
                Object a = first.get(i), b = second.get(i);
                check(invoke(a, "getNumVertices", new Class<?>[0]).equals(invoke(b, "getNumVertices", new Class<?>[0])), "native vertex count");
                check(invoke(a, "getNumFaces", new Class<?>[0]).equals(invoke(b, "getNumFaces", new Class<?>[0])), "native face count");
                sameBuffer(a, b, "getPositionBuffer", new Class<?>[0]);
                sameBuffer(a, b, "getTexCoordBuffer", new Class<?>[]{int.class}, 0);
                List<?> bones = (List<?>) invoke(a, "getBones", new Class<?>[0]);
                List<?> derivedBones = (List<?>) invoke(b, "getBones", new Class<?>[0]);
                check(bones.size() == derivedBones.size(), "native bone counts");
                for (int k = 0; k < bones.size(); k++) {
                    check(invoke(bones.get(k), "getName", new Class<?>[0]).equals(invoke(derivedBones.get(k), "getName", new Class<?>[0])), "native bone names");
                }
                System.out.println("NATIVE_MODEL " + pair[1] + " vertices=" + invoke(b, "getNumVertices", new Class<?>[0])
                    + " faces=" + invoke(b, "getNumFaces", new Class<?>[0]) + " bones=" + derivedBones.size() + " PASS");
            }
        }
        String text = new String(Files.readAllBytes(media.resolve("scripts/models_FreshnessLunchbox.txt")), StandardCharsets.UTF_8);
        String model = text.substring(text.indexOf("    model "), text.lastIndexOf('}')).trim();
        Class<?> modelClass = Class.forName("zombie.scripting.objects.ModelScript");
        Object script = modelClass.getConstructor().newInstance();
        modelClass.getMethod("Load", String.class, String.class).invoke(script, "SuQingFreshnessLunchbox_Ground", model);
        check("WorldItems/SuQingFreshnessLunchbox/SuQingFreshnessLunchbox_Ground".equals(modelClass.getField("meshName").get(script)), "native ModelScript mesh");
        check("Clothes/Bag/SuQingFreshnessLunchbox".equals(modelClass.getField("textureName").get(script)), "native ModelScript texture");
        check(Math.abs(modelClass.getField("scale").getFloat(script) - .4f) < .000001f, "native ModelScript scale");
        System.out.println("NATIVE_MODEL_SCRIPT mesh/texture/scale PASS");
        System.out.println("NATIVE_ASSET_SUMMARY assertions=" + assertions + " failures=0 game_started=false world_created=false gl_context=false");
    }
}
