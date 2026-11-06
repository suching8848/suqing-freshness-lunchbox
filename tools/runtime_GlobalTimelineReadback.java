import java.lang.reflect.*;
import java.nio.*;
import java.nio.file.*;
import java.util.*;
/** Read-only native Kahlua table decoder. No world, Lua game runtime or save loader. */
public class runtime_GlobalTimelineReadback {
    static String quote(String s){return "\""+s.replace("\\","\\\\").replace("\"","\\\"").replace("\n","\\n").replace("\r","\\r")+"\"";}
    static String json(Object value)throws Exception{
        if(value==null)return "null";
        if(value instanceof Number||value instanceof Boolean)return value.toString();
        if(value instanceof String)return quote((String)value);
        Map<?,?> map=(Map<?,?>)value.getClass().getField("delegate").get(value);
        StringBuilder s=new StringBuilder("{");boolean first=true;
        for(Map.Entry<?,?> e:map.entrySet()){if(!first)s.append(',');first=false;s.append(quote(e.getKey().toString())).append(':').append(json(e.getValue()));}
        return s.append('}').toString();
    }
    public static void main(String[]args)throws Exception{
        byte[] bytes=Files.readAllBytes(Paths.get(args[0]));ByteBuffer input=ByteBuffer.wrap(bytes);
        int version=input.getInt(),count=input.getInt(),matches=0;
        Method read=Class.forName("zombie.GameWindow").getMethod("ReadString",ByteBuffer.class);
        Class<?> tc=Class.forName("se.krka.kahlua.j2se.KahluaTableImpl");
        for(int i=0;i<count;i++){
            int blockOffset=input.position(),length=input.getInt(),start=input.position(),end=start+length;
            if(length<2||end>bytes.length)throw new AssertionError("invalid global block length");
            String key=(String)read.invoke(null,input);int tableOffset=input.position();
            if(key.equals("SuQingFreshnessLunchboxTimeline")){
                Object table=tc.getConstructor(Map.class).newInstance(new LinkedHashMap<Object,Object>());
                ByteBuffer bounded=input.duplicate();bounded.limit(end);
                tc.getMethod("load",ByteBuffer.class,int.class).invoke(table,bounded,version);
                if(bounded.position()!=end)throw new AssertionError("native table boundary mismatch");
                matches++;
                System.out.println("{\"world_version\":"+version+",\"global_tables\":"+count+",\"block_offset\":"+blockOffset+",\"block_length\":"+length+",\"table_offset\":"+tableOffset+",\"end_offset\":"+end+",\"timeline\":"+json(table)+"}");
            }
            input.position(end);
        }
        if(matches!=1||input.position()!=bytes.length)throw new AssertionError("global table count or final boundary mismatch");
    }
}
