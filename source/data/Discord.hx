package data;

// ────────────────────────────────────────────────────────────────────────────
// Discord.hx — Rich Presence via discord_rpc
//
// discord_rpc only exists on desktop (Windows/Mac/Linux).
// Android is also cpp but does NOT have discord_rpc — use #if desktop.
// ────────────────────────────────────────────────────────────────────────────

#if desktop

import Sys.sleep;
import discord_rpc.DiscordRpc;

using StringTools;

class DiscordClient
{
	// ── Valores por defecto del engine (hardcoded) ────────────────────────────
	static inline var DEFAULT_CLIENT_ID:String    = "1492944020366692597";
	static inline var DEFAULT_LARGE_IMAGE:String  = "icon";
	static inline var DEFAULT_IMAGE_TEXT:String   = "FNF' Cool Engine";
	static inline var DEFAULT_MENU_DETAILS:String = "In the Menu";

	// ── Config activa (puede ser sobreescrita por un mod) ─────────────────────
	public static var activeClientId:String    = DEFAULT_CLIENT_ID;
	public static var activeLargeImageKey:String  = DEFAULT_LARGE_IMAGE;
	public static var activeLargeImageText:String = DEFAULT_IMAGE_TEXT;
	public static var activeMenuDetails:String = DEFAULT_MENU_DETAILS;

	/** true si el RPC fue iniciado al menos una vez. */
	static var _running:Bool = false;

	public function new()
	{
		trace("Discord Client starting...");
		DiscordRpc.start({
			clientID: activeClientId,
			onReady: onReady,
			onError: onError,
			onDisconnected: onDisconnected
		});
		_running = true;
		trace("Discord Client started.");

		while (true)
		{
			DiscordRpc.process();
			sleep(2);
		}

		DiscordRpc.shutdown();
	}

	public static function shutdown()
	{
		DiscordRpc.shutdown();
		_running = false;
	}

	static function onReady()
	{
		DiscordRpc.presence({
			details: activeMenuDetails,
			state: null,
			largeImageKey: activeLargeImageKey,
			largeImageText: activeLargeImageText
		});
	}

	static function onError(_code:Int, _message:String)
	{
		trace('Error! $_code : $_message');
	}

	static function onDisconnected(_code:Int, _message:String)
	{
		trace('Disconnected! $_code : $_message');
	}

	public static function initialize()
	{
		var DiscordDaemon = sys.thread.Thread.create(() ->
		{
			new DiscordClient();
		});
		trace("Discord Client initialized");
	}

	/**
	 * Aplica la configuración de Discord de un mod.
	 * Si info es null, restaura los valores por defecto del engine.
	 *
	 * Si el mod define un clientId distinto al actual, reinicia el RPC
	 * con el nuevo ID de aplicación (requiere que el mod tenga su propia
	 * app en el Discord Developer Portal con las imágenes subidas).
	 *
	 * Llamar desde Main.hx en onModChanged y al arrancar.
	 */
	public static function applyModConfig(info:Null<mods.ModManager.ModInfo>):Void
	{
		final dc = info?.discord;

		final newClientId    = dc?.clientId      ?? DEFAULT_CLIENT_ID;
		final newImageKey    = dc?.largeImageKey  ?? DEFAULT_LARGE_IMAGE;
		final newImageText   = dc?.largeImageText ?? DEFAULT_IMAGE_TEXT;
		final newMenuDetails = dc?.menuDetails   ?? DEFAULT_MENU_DETAILS;

		final clientChanged = (newClientId != activeClientId);

		activeLargeImageKey  = newImageKey;
		activeLargeImageText = newImageText;
		activeMenuDetails    = newMenuDetails;

		if (clientChanged)
		{
			// clientId distinto → hay que reiniciar RPC con el nuevo app ID
			activeClientId = newClientId;
			trace('[Discord] clientId cambió → reiniciando RPC con "$newClientId"');
			if (_running)
			{
				DiscordRpc.shutdown();
				_running = false;
			}
			// Lanzar nuevo hilo con el clientId actualizado
			initialize();
		}
		else
		{
			// Mismo clientId — solo actualizar la presence con los nuevos valores
			if (_running)
			{
				DiscordRpc.presence({
					details: activeMenuDetails,
					state: null,
					largeImageKey: activeLargeImageKey,
					largeImageText: activeLargeImageText
				});
			}
		}

		trace('[Discord] Config applied → clientId=$activeClientId imageKey=$activeLargeImageKey menuDetails="$activeMenuDetails"');
	}

	public static function changePresence(details:String, state:Null<String>, ?smallImageKey:String,
		?hasStartTimestamp:Bool, ?endTimestamp:Float)
	{
		var startTimestamp:Float = if (hasStartTimestamp) Date.now().getTime() else 0;

		if (endTimestamp > 0)
			endTimestamp = startTimestamp + endTimestamp;

		DiscordRpc.presence({
			details: details,
			state: state,
			largeImageKey: activeLargeImageKey,
			largeImageText: activeLargeImageText,
			smallImageKey: smallImageKey,
			startTimestamp: Std.int(startTimestamp / 1000),
			endTimestamp: Std.int(endTimestamp / 1000)
		});
	}
}

#else

// ── Stub for non-desktop targets (android, neko, html5) ─────────────────────
// Provides the same public API so all imports resolve, but does nothing.
class DiscordClient
{
	public static var activeClientId:String     = "";
	public static var activeLargeImageKey:String   = "";
	public static var activeLargeImageText:String  = "";
	public static var activeMenuDetails:String  = "";
	public static inline function initialize():Void {}
	public static inline function shutdown():Void {}
	public static inline function applyModConfig(?info:mods.ModManager.ModInfo):Void {}
	public static inline function changePresence(details:String, state:Null<String>,
		?smallImageKey:String, ?hasStartTimestamp:Bool, ?endTimestamp:Float):Void {}
}

#end
