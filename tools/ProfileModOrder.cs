// SCS ScsC container layout reference:
// https://github.com/avoinescu/ets2-decrypt/blob/main/decoder/decoder.go
// Own implementation for editing only a user's active_mods configuration.
using System;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace Ets2Mods {
 public static class ProfileModOrder {
  public static void ReplaceFile(string temp,string target) {File.Replace(temp,target,null);}
  public static string Decode(byte[] raw) {
   if(raw.Length < 4 || raw.Length > 64000000) throw new InvalidDataException("Geçersiz profil boyutu.");
   byte[] data=raw;
   if(Encoding.ASCII.GetString(raw,0,4)=="ScsC") {
    if(raw.Length<72 || (raw.Length-56)%16!=0) throw new InvalidDataException("Eksik ScsC profili.");
    using(var aes=Aes.Create()) {
     aes.Key=new byte[]{0x2a,0x5f,0xcb,0x17,0x91,0xd2,0x2f,0xb6,0x02,0x45,0xb3,0xd8,0x36,0x9e,0xd0,0xb2,0xc2,0x73,0x71,0x56,0x3f,0xbf,0x1f,0x3c,0x9e,0xdf,0x6b,0x11,0x82,0x5a,0x5d,0x0a};
     byte[] iv=new byte[16]; Buffer.BlockCopy(raw,36,iv,0,16); aes.IV=iv;
     using(var dec=aes.CreateDecryptor()) data=dec.TransformFinalBlock(raw,56,raw.Length-56);
    }
    if(data.Length<6 || (data[0]&15)!=8 || ((data[0]<<8)+data[1])%31!=0 || (data[1]&32)!=0) throw new InvalidDataException("Geçersiz zlib profili.");
    byte[] compressed=data;
    using(var input=new MemoryStream(compressed,2,compressed.Length-6))
    using(var deflate=new DeflateStream(input,CompressionMode.Decompress))
    using(var output=new MemoryStream()) {
     byte[] buffer=new byte[8192]; int n;
     while((n=deflate.Read(buffer,0,buffer.Length))>0) {if(output.Length+n>64000000) throw new InvalidDataException("Profil çok büyük."); output.Write(buffer,0,n);}
     data=output.ToArray();
    }
    uint a=1,b=0; foreach(byte value in data){a=(a+value)%65521;b=(b+a)%65521;}
    int p=compressed.Length-4; uint checksum=((uint)compressed[p]<<24)|((uint)compressed[p+1]<<16)|((uint)compressed[p+2]<<8)|compressed[p+3];
    if(((b<<16)|a)!=checksum) throw new InvalidDataException("Profil sağlama toplamı hatalı.");
   }
   string text=new UTF8Encoding(false,true).GetString(data);
   if(!text.StartsWith("SiiNunit") || Regex.Matches(text,@"(?m)^\s*user_profile\s*:").Count!=1) throw new InvalidDataException("Desteklenmeyen profil biçimi.");
   return text;
  }
  public static string Replace(string text,string[] entries) {
   var pattern=new Regex(@"(?m)^[ \t]*active_mods(?:\[\d+\])?[ \t]*:[^\r\n]*(?:\r*\n|$)");
   var count=new Regex(@"(?m)^[ \t]*active_mods[ \t]*:[ \t]*(\d+)[ \t\r]*$");
   var matches=count.Matches(text);
   if(matches.Count!=1) throw new InvalidDataException("Profil mod listesi bulunamadı/tekrarlanıyor.");
   var all=pattern.Matches(text); var first=all[0];
   int oldCount=int.Parse(matches[0].Groups[1].Value);
   if(all.Count!=oldCount+1) throw new InvalidDataException("Profil mod listesi eksik.");
   if(first.Index!=matches[0].Index) throw new InvalidDataException("Beklenmeyen mod listesi sırası.");
   string newline=text.Contains("\r\r\n")?"\r\r\n":text.Contains("\r\n")?"\r\n":"\n";
   var block=new StringBuilder(" active_mods: "+entries.Length+newline);
   for(int i=0;i<entries.Length;i++) {
    if(entries[i].Contains("\n") || entries[i].Contains("\r")) throw new InvalidDataException("Geçersiz mod adı.");
    block.Append(" active_mods["+i+"]: \""+entries[i].Replace("\\","\\\\").Replace("\"","\\\"")+"\""+newline);
   }
   string stripped=pattern.Replace(text,"");
   return stripped.Insert(first.Index,block.ToString());
  }
 }
}
