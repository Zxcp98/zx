import discord
from discord import app_commands
from discord.ext import commands
from datetime import datetime

# ==============================
# KONFIGURASI
# ==============================

GUILD_ID = 1414219665428844606  # ID server untuk sync cepat

# Role & user yang boleh pakai bot
ALLOWED_ROLE_ID = 1428635556249604117
ALLOWED_USER_ID = 893729892951289858


# ==============================
# SETUP BOT
# ==============================
intents = discord.Intents.all()
bot = commands.Bot(command_prefix="!", intents=intents)


# ==============================
# EVENT: BOT ONLINE
# ==============================
@bot.event
async def on_ready():
    print(f"✅ Bot {bot.user} sudah online!")
    try:
        guild = discord.Object(id=GUILD_ID)
        synced = await bot.tree.sync(guild=guild)
        print(f"🔁 {len(synced)} command di-sync ke guild {GUILD_ID}:")
        for cmd in synced:
            print(f"   • /{cmd.name}")
        print("📋 Semua command aktif dan siap digunakan!")
    except Exception as e:
        print(f"❌ Gagal sync commands: {e}")


# ==============================
# CEK IZIN AKSES
# ==============================
def is_allowed(user: discord.Member):
    has_role = any(role.id == ALLOWED_ROLE_ID for role in user.roles)
    return has_role or user.id == ALLOWED_USER_ID


# ==============================
# /text → kirim teks biasa
# ==============================
@bot.tree.command(name="text", description="Kirim teks bebas lewat bot")
@app_commands.describe(content="Isi teks yang ingin dikirim")
@app_commands.guilds(discord.Object(id=GUILD_ID))
async def text(interaction: discord.Interaction, content: str):
    if not is_allowed(interaction.user):
        await interaction.response.send_message("🚫 Kamu tidak diizinkan memakai bot ini.", ephemeral=True)
        return

    if not content.strip():
        await interaction.response.send_message("⚠️ Teks tidak boleh kosong!", ephemeral=True)
        return

    await interaction.response.send_message("✅ Pesan dikirim!", ephemeral=True)
    await interaction.channel.send(content)
    print(f"[LOG] /text oleh {interaction.user} -> {content}")


# ==============================
# /textembed → kirim embed dengan teks + gambar
# ==============================
@bot.tree.command(name="textembed", description="Kirim embed dengan teks dan file (gambar/GIF wajib dilampirkan)")
@app_commands.describe(
    title="Judul embed",
    description="Isi teks embed",
    color="Warna embed hex tanpa # (contoh: FF0000)",
    attachment="File gambar/GIF untuk embed"
)
@app_commands.guilds(discord.Object(id=GUILD_ID))
async def textembed(
    interaction: discord.Interaction,
    title: str,
    description: str,
    color: str = "5865F2",
    attachment: discord.Attachment = None
):
    if not is_allowed(interaction.user):
        await interaction.response.send_message("🚫 Kamu tidak diizinkan memakai bot ini.", ephemeral=True)
        return

    if not attachment:
        await interaction.response.send_message("⚠️ Harus melampirkan file (gambar/GIF)!", ephemeral=True)
        return

    try:
        color_value = int(color, 16)
    except ValueError:
        await interaction.response.send_message("❌ Warna salah! Gunakan format hex tanpa #.", ephemeral=True)
        return

    embed = discord.Embed(title=title, description=description, color=color_value)
    embed.set_footer(text="Sent by Seraphin")

    await interaction.response.defer(ephemeral=True)

    try:
        file = await attachment.to_file()
        embed.set_image(url=f"attachment://{file.filename}")
        await interaction.channel.send(embed=embed, file=file)
        await interaction.followup.send("✅ Embed dengan file berhasil dikirim!", ephemeral=True)
        print(f"[LOG] /textembed oleh {interaction.user} -> {attachment.filename}")
    except Exception as e:
        await interaction.followup.send(f"❌ Gagal kirim embed/file: {e}", ephemeral=True)


# ==============================
# /fileembed → kirim hanya file dalam embed
# ==============================
@bot.tree.command(name="fileembed", description="Kirim hanya file gambar/GIF dalam embed (tanpa teks)")
@app_commands.describe(attachment="File gambar/GIF yang ingin dikirim")
@app_commands.guilds(discord.Object(id=GUILD_ID))
async def fileembed(interaction: discord.Interaction, attachment: discord.Attachment):
    if not is_allowed(interaction.user):
        await interaction.response.send_message("🚫 Kamu tidak diizinkan memakai bot ini.", ephemeral=True)
        return

    await interaction.response.defer(ephemeral=True)

    try:
        file = await attachment.to_file()
        embed = discord.Embed(color=0x5865F2)
        embed.set_image(url=f"attachment://{file.filename}")
        embed.set_footer(text="Sent by Seraphin")

        await interaction.channel.send(embed=embed, file=file)
        await interaction.followup.send("✅ File embed berhasil dikirim!", ephemeral=True)
        print(f"[LOG] /fileembed oleh {interaction.user} -> {attachment.filename}")
    except Exception as e:
        await interaction.followup.send(f"❌ Gagal kirim file embed: {e}", ephemeral=True)


# ==============================
# /dm → kirim pesan langsung ke user
# ==============================
@bot.tree.command(name="dm", description="Kirim pesan ke DM user tertentu (hanya untuk admin terpilih)")
@app_commands.describe(
    user="User yang ingin dikirimi pesan",
    message="Isi pesan yang ingin dikirim ke DM"
)
@app_commands.guilds(discord.Object(id=GUILD_ID))
async def dm(interaction: discord.Interaction, user: discord.User, message: str):
    if not is_allowed(interaction.user):
        await interaction.response.send_message("🚫 Kamu tidak diizinkan memakai bot ini.", ephemeral=True)
        return

    await interaction.response.defer(ephemeral=True)
    try:
        await user.send(message)
        await interaction.followup.send(f"✅ Pesan berhasil dikirim ke {user.mention}!", ephemeral=True)
        print(f"[LOG] /dm oleh {interaction.user} -> {user} : {message}")
    except discord.Forbidden:
        await interaction.followup.send("❌ Gagal kirim DM — user menonaktifkan pesan langsung.", ephemeral=True)
    except Exception as e:
        await interaction.followup.send(f"❌ Gagal kirim DM: {e}", ephemeral=True)


# ==============================
# /update → kirim embed update custom lengkap
# ==============================
@bot.tree.command(name="update", description="Kirim pengumuman update lengkap dengan link custom")
@app_commands.describe(
    tier="Tipe / versi update (contoh: Beta, Stable, v1.2)",
    product="Nama produk yang diupdate",
    changelog="Daftar perubahan (pisahkan dengan koma, titik koma, atau baris baru)"
)
@app_commands.guilds(discord.Object(id=GUILD_ID))
async def update(
    interaction: discord.Interaction,
    tier: str,
    product: str,
    changelog: str,
):
    if not is_allowed(interaction.user):
        await interaction.response.send_message("🚫 Kamu tidak diizinkan memakai bot ini.", ephemeral=True)
        return

    # 🔹 Format changelog supaya turun ke bawah
    lines = [line.strip() for line in changelog.replace(";", "\n").replace(",", "\n").split("\n") if line.strip()]
    formatted_lines = []
    for line in lines:
        lower = line.lower()
        if any(word in lower for word in ["remove", "delete", "fix", "error", "bug"]):
            prefix = "- "
        elif any(word in lower for word in ["add", "new", "improv", "update", "create"]):
            prefix = "+ "
        else:
            prefix = "! "
        formatted_lines.append(prefix + line)

    changelog_text = "\n".join(formatted_lines)

    embed = discord.Embed(
        title="Seraphin Has Been Update",
        description=f"⚠️ **[ `{product}` ]** :  Change Log **[ `{tier}` ]**",
        color=0x2f3136
    )

    embed.add_field(
        name="**ChangeLogs**",
        value=f"```diff\n{changelog_text}\n```",
        inline=False
    )

    embed.add_field(
        name="\u200b",
        value=(
            "**Please Execute Again**, and use new updated version now\n"
            f"If u got a bug, report on <#1414518549887713354>\n"
        ),
        inline=False
    )

    embed.set_footer(
        text=f"{product} Official Update",
        icon_url="https://cdn.discordapp.com/attachments/1371799622317510688/1437785002879484048/file_00000000df3c7207a5e646df01606670.png"
    )
    embed.set_thumbnail(
        url="https://cdn.discordapp.com/attachments/1371799622317510688/1437785002879484048/file_00000000df3c7207a5e646df01606670.png"
    )

    mention_text = ""
    await interaction.response.send_message("✅ Update dikirim!", ephemeral=True)
    await interaction.channel.send(mention_text, embed=embed)
    print(f"[LOG] /update oleh {interaction.user} -> {product} ({tier})")


# ==============================
# JALANKAN BOT
# ==============================
if __name__ == "__main__":
    bot.run(BOT_TOKEN)
