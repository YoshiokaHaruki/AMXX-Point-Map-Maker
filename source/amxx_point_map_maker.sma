public stock const PluginName[ ] =			"[AMXX] Addon: Point Map Maker";
public stock const PluginVersion[ ] =		"1.0.2";
public stock const PluginAuthor[ ] =		"Yoshioka Haruki";

/* ~ [ Includes ] ~ */
#include <amxmodx>
#include <fakemeta>
#include <xs>
#include <reapi>
#include <json>

/* ~ [ Plugin Settings ] ~ */
/**
 * Add settings menu to amxmodmenu
 */
// #define AddMenuToAmxModMenu

new const PluginPrefix[ ] =					"Point Maker"; // Plugin prefix (in chat and natives)
new const MainFolder[ ] =					"/PointMaker"; // Main folder with map points
new const PointSprite[ ] =					"sprites/laserbeam.spr";
new const PluginSounds[ ][ ] = {
	// This sounds used by 'spk'
	"sound/buttons/blip1.wav", // Add Point
	"sound/buttons/blip2.wav", // Delete Point
	"sound/buttons/button2.wav", // Error
	"sound/common/menu1.wav", // Save File
	"sound/common/menu2.wav" // Delete All Points
}
/**
 * The name of the objects for .json file.
 * When using native - specify one of these names. If the name is not found, "general" will be used
 * Add new ones AFTER "general"
 */
new const ObjectNames[ ][ ] = {
	"general", "presents", "market_place"
};
#define EnableIgnoreList
#if defined EnableIgnoreList
	/**
	 * The list of entities that we will skip when checking whether the point is not free.
	 * If, when checking, we find one of these entities, the point is free.
	 */
	new const IgnoreEntitiesList[ ][ ] = {
		"weaponbox", "armoury_entity", "grenade"
	};
#endif
new const DebugBeamColors[ ][ ] = {
	{ 255, 255, 255 }, // Not active object 
	{ 0, 255, 0 } // Active object
}
const Float: NearOriginDistance =			64.0; // Maximum distance when removing a point
const MenuPointMaker_Buttons =				( MENU_KEY_1|MENU_KEY_2|MENU_KEY_3|MENU_KEY_7|MENU_KEY_8|MENU_KEY_9|MENU_KEY_0 );

/* ~ [ Macroses ] ~ */
#if !defined Vector3
	#define Vector3(%0)						Float: %0[ 3 ]
#endif

#if !defined MAX_CONFIG_PATH_LENGHT
	#define MAX_CONFIG_PATH_LENGHT			128
#endif

#define BIT_PLAYER(%0)						( BIT( %0 - 1 ) )
#define BIT_SUB(%0,%1)						( %0 &= ~%1 )
#define BIT_VALID(%0,%1)					( ( %0 & %1 ) == %1 )
#define BIT_INVERT(%0,%1)					( %0 ^= %1 )
#define BIT_CLEAR(%0)						( %0 = 0 )

#define IsNullString(%0)					bool: ( %0[ 0 ] == EOS )
#define SetFormatex(%0,%1,%2)				( %1 = formatex( %0, charsmax( %0 ), %2 ) )
#define AddFormatex(%0,%1,%2)				( %1 += formatex( %0[ %1 ], charsmax( %0 ) - %1, %2 ) )

/* ~ [ Params ] ~ */
new gl_iObjectNow;
new gl_iPointsCount;
new gl_bitsUserShowAllPoints;
new gl_iszModelIndex_PointSprite;
new gl_szMapName[ MAX_NAME_LENGTH ];
new gl_szFilePath[ MAX_CONFIG_PATH_LENGHT ];
new HookChain: gl_HookChain_Player_PreThink_Post;

enum ePointsData {
	PointObjectName[ MAX_NAME_LENGTH ],
	Vector3( PointOrigin )
};
new Array: gl_arMapPoints;

enum {
	Sound_AddPoint,
	Sound_DeletePoint,
	Sound_Error,
	Sound_SaveFile,
	Sound_DeleteAllPoints
};

/* ~ [ AMX Mod X ] ~ */
public plugin_natives( )
{
	register_native( "pmm_get_random_point", "native_get_random_point" );
	register_native( "pmm_get_random_points", "native_get_random_points" );
	register_native( "pmm_get_all_points", "native_get_all_points" );
	register_native( "pmm_free_array", "native_free_array" );
}

public plugin_precache( )
{
	/* -> Precache Models <- */
	gl_iszModelIndex_PointSprite = engfunc( EngFunc_PrecacheModel, PointSprite );

	/* -> Create Array's <- */
	gl_arMapPoints = ArrayCreate( ePointsData );

	/* -> Other <- */
	rh_get_mapname( gl_szMapName, charsmax( gl_szMapName ), MNT_TRUE );

	get_localinfo( "amxx_configsdir", gl_szFilePath, charsmax( gl_szFilePath ) );
	strcat( gl_szFilePath, MainFolder, charsmax( gl_szFilePath ) );

	if ( !dir_exists( gl_szFilePath ) )
		mkdir( gl_szFilePath );

	strcat( gl_szFilePath, fmt( "/%s.json", gl_szMapName ), charsmax( gl_szFilePath ) );

	JSON_Points_Load( gl_arMapPoints );
}

public plugin_init( )
{
	register_plugin( PluginName, PluginVersion, PluginAuthor );

	/* -> ReGameDLL <- */
	DisableHookChain( gl_HookChain_Player_PreThink_Post =
		RegisterHookChain( RG_CBasePlayer_PreThink, "RG_CBasePlayer__PreThink_Post", true )
	);

	/* -> Lang Files <- */
	register_dictionary( "point_map_maker.txt" );

	/* -> Create Menus <- */
	register_menucmd( register_menuid( "MenuPointMaker_Show" ), MenuPointMaker_Buttons, "MenuPointMaker_Handler" );

	/* -> Console Commands <- */
	register_concmd( "amx_point_maker", "ConsoleCommand__PointMaker", ADMIN_RCON, "Open menu for create points." );
}

#if defined AddMenuToAmxModMenu
	#include <amxmisc>

	public plugin_cfg( )
	{
		/* -> Add system to AMX Mod Menu <- */
		AddMenuItem( "Point Map Maker", "amx_point_maker", ADMIN_RCON, PluginName );
	}
#endif

public client_disconnected( pPlayer )
{
	BIT_SUB( gl_bitsUserShowAllPoints, BIT_PLAYER( pPlayer ) );

	if ( !gl_bitsUserShowAllPoints )
		DisableHookChain( gl_HookChain_Player_PreThink_Post );
}

/* ~ [ ReGameDLL ] ~ */
public RG_CBasePlayer__PreThink_Post( const pPlayer )
{
	if ( !gl_bitsUserShowAllPoints || !gl_iPointsCount )
	{
		DisableHookChain( gl_HookChain_Player_PreThink_Post );
		return;
	}

	if ( !BIT_VALID( gl_bitsUserShowAllPoints, BIT_PLAYER( pPlayer ) ) )
		return;

	static Float: flLastUpdate;
	static Float: flGameTime; flGameTime = get_gametime( );

	if ( flLastUpdate < flGameTime )
	{
		static i, aTempData[ ePointsData ], Vector3( vecOrigin );
		for ( i = 0; i < gl_iPointsCount; i++ )
		{
			ArrayGetArray( gl_arMapPoints, i, aTempData );
			xs_vec_copy( aTempData[ PointOrigin ], vecOrigin );
			
			UTIL_TE_BEAMPOINTS_DEBUG( MSG_ONE_UNRELIABLE, pPlayer, vecOrigin, 10, DebugBeamColors[ equal( aTempData[ PointObjectName ], ObjectNames[ gl_iObjectNow ] ) ] );
		}

		flLastUpdate = flGameTime + 1.0;
	}
}

/* ~ [ Other ] ~ */
public ConsoleCommand__PointMaker( const pCaller, const bitsFlags )
{
	if ( !is_user_connected( pCaller ) )
	{
		console_print( pCaller, "%l", "PMM_Console_OnlyForPlayer" );
		return PLUGIN_HANDLED;
	}

	if ( ~get_user_flags( pCaller ) & bitsFlags )
		return PLUGIN_HANDLED;

	MenuPointMaker_Show( pCaller );
	return PLUGIN_HANDLED;
}

/* ~ [ Menus ] ~ */
public MenuPointMaker_Show( const pPlayer )
{
	if ( gl_arMapPoints == Invalid_Array )
		return;

	new szBuffer[ MAX_MENU_LENGTH ], iLen;

	SetFormatex( szBuffer, iLen, "%l^n^n", "PMM_Menu_Title", gl_szMapName, gl_iPointsCount );

	AddFormatex( szBuffer, iLen, "\y1. \w%l^n", "PMM_Menu_AddPoint" );
	AddFormatex( szBuffer, iLen, "\y2. \w%l^n", "PMM_Menu_RemovePoint" );
	AddFormatex( szBuffer, iLen, "\y3. \w%l^n", "PMM_Menu_SwitchObject", ObjectNames[ gl_iObjectNow ] );
	AddFormatex( szBuffer, iLen, "^n\y7. \w%l^n", "PMM_Menu_ShowPoints", BIT_VALID( gl_bitsUserShowAllPoints, BIT_PLAYER( pPlayer ) ) ? "\yON\d" : "OFF" );
	AddFormatex( szBuffer, iLen, "^n\y8. \w%l^n", "PMM_Menu_RemovePoints" );
	AddFormatex( szBuffer, iLen, "\y9. \w%l^n", "PMM_Menu_SavePoints" );

	AddFormatex( szBuffer, iLen, "^n\y0. \w%l", "PMM_Menu_Exit" );

	set_member( pPlayer, m_iMenu, Menu_OFF );
	show_menu( pPlayer, MenuPointMaker_Buttons, szBuffer, -1, "MenuPointMaker_Show" )
}

public MenuPointMaker_Handler( const pPlayer, const iMenuKey )
{
	switch ( iMenuKey ) {
		case 0: {
			new aTempData[ ePointsData ];
			copy( aTempData[ PointObjectName ], charsmax( aTempData[ PointObjectName ] ), ObjectNames[ gl_iObjectNow ] );
			get_entvar( pPlayer, var_origin, aTempData[ PointOrigin ] );

			ArrayPushArray( gl_arMapPoints, aTempData );
			gl_iPointsCount++;

			UTIL_PlaySound( pPlayer, PluginSounds[ Sound_AddPoint ] );

			new Vector3( vecOrigin ); xs_vec_copy( aTempData[ PointOrigin ], vecOrigin );
			UTIL_TE_IMPLOSION( MSG_ONE_UNRELIABLE, pPlayer, vecOrigin );

			client_print_color( pPlayer, print_team_default, "^4[%s]^1 %l ^3#%i^1. %l: ^3^"%s^" ^1%l: ^3%.2f %.2f %.2f", PluginPrefix, "PMM_Chat_AddedPoint", gl_iPointsCount, "PMM_Chat_Object", aTempData[ PointObjectName ], "PMM_Chat_Origin", aTempData[ PointOrigin ][ 0 ], aTempData[ PointOrigin ][ 1 ], aTempData[ PointOrigin ][ 2 ] );
		}
		case 1: {
			if ( gl_iPointsCount )
			{
				new aTempData[ ePointsData ];
				new Vector3( vecOrigin ); UTIL_GetEyePointAiming( pPlayer, 8192.0, vecOrigin );
				new iFindOrigin = -1, Float: flDistance, Float: flLastDistance = NearOriginDistance;

				for ( new i = 0; i < gl_iPointsCount; i++ )
				{
					ArrayGetArray( gl_arMapPoints, i, aTempData );

					// xs_vec_distance_2d because if the point is in the air, then it will be difficult to hook it
					flDistance = xs_vec_distance_2d( vecOrigin, aTempData[ PointOrigin ] );
					if ( flDistance < flLastDistance )
					{
						flLastDistance = flDistance;
						iFindOrigin = i;
					}
				}

				if ( iFindOrigin != -1 )
				{
					ArrayGetArray( gl_arMapPoints, iFindOrigin, aTempData );
					ArrayDeleteItem( gl_arMapPoints, iFindOrigin );

					gl_iPointsCount--;
					client_print_color( pPlayer, print_team_default, "^4[%s]^1 %l ^3#%i^1. %l: ^3^"%s^" ^1%l: ^3%.2f %.2f %.2f", PluginPrefix, "PMM_Chat_DeletePoint", iFindOrigin + 1, "PMM_Chat_Object", aTempData[ PointObjectName ], "PMM_Chat_Origin", aTempData[ PointOrigin ][ 0 ], aTempData[ PointOrigin ][ 1 ], aTempData[ PointOrigin ][ 2 ] );

					new Vector3( vecOrigin ); xs_vec_copy( aTempData[ PointOrigin ], vecOrigin );
					UTIL_TE_TELEPORT( MSG_ONE_UNRELIABLE, pPlayer, vecOrigin );

					UTIL_PlaySound( pPlayer, PluginSounds[ Sound_DeletePoint ] );

					if ( !gl_iPointsCount )
						BIT_CLEAR( gl_bitsUserShowAllPoints );
				}
				else
				{
					client_print_color( pPlayer, print_team_default, "^4[%s]^1 %l", PluginPrefix, "PMM_Chat_NotFind", NearOriginDistance );
					UTIL_PlaySound( pPlayer, PluginSounds[ Sound_Error ] );
				}
			}
			else
			{
				client_print_color( pPlayer, print_team_default, "^4[%s]^1 %l", PluginPrefix, "PMM_Chat_NoPoints" );
				UTIL_PlaySound( pPlayer, PluginSounds[ Sound_Error ] );
			}
		}
		case 2: {
			if ( ++gl_iObjectNow && gl_iObjectNow >= sizeof ObjectNames )
				gl_iObjectNow = 0;
		}
		case 6: {
			if ( gl_iPointsCount )
				BIT_INVERT( gl_bitsUserShowAllPoints, BIT_PLAYER( pPlayer ) );
			else
			{
				client_print_color( pPlayer, print_team_default, "^4[%s]^1 %l %l", PluginPrefix, "PMM_Chat_NoPoints", "PMM_Chat_AddPointForUse" );
				UTIL_PlaySound( pPlayer, PluginSounds[ Sound_Error ] );
			}

			( gl_bitsUserShowAllPoints ) ? EnableHookChain( gl_HookChain_Player_PreThink_Post ) : DisableHookChain( gl_HookChain_Player_PreThink_Post );
		}
		case 7: {
			ArrayClear( gl_arMapPoints );

			BIT_CLEAR( gl_bitsUserShowAllPoints );
			gl_iPointsCount = 0;

			client_print_color( pPlayer, print_team_default, "^4[%s]^1 %l", PluginPrefix, "PMM_Chat_DeteleAllPoints" );
			UTIL_PlaySound( pPlayer, PluginSounds[ Sound_DeleteAllPoints ] );
		}
		case 8: {
			client_print_color( pPlayer, print_team_default, "^4[%s]^1 %l", PluginPrefix, "PMM_Chat_SavePoints", gl_szFilePath );
			UTIL_PlaySound( pPlayer, PluginSounds[ Sound_SaveFile ] );

			JSON_Points_Save( gl_arMapPoints );
		}
		case 9: {
			return;
		}
	}

	MenuPointMaker_Show( pPlayer );
}

/* ~ [ JSON ] ~ */
public JSON_Points_Load( const Array: arHandle )
{
	if ( !file_exists( gl_szFilePath ) )
		return;

	new JSON: JSON_Handle = json_parse( gl_szFilePath, true );
	if ( JSON_Handle == Invalid_JSON )
	{
		server_print( "[%s] Invalid read file: ^"%s^"", PluginPrefix, gl_szFilePath );
		return;
	}

	new iJsonHandleSize = json_object_get_count( JSON_Handle );
	if ( !iJsonHandleSize )
	{
		json_free( JSON_Handle );
		return;
	}

	new iJsonArraySize;
	new JSON: JSON_PointObject = Invalid_JSON;
	new JSON: JSON_PointOrigin = Invalid_JSON;
	new aTempData[ ePointsData ];

	for ( new i, j, k; i < iJsonHandleSize; i++ )
	{
		json_object_get_name( JSON_Handle, i, aTempData[ PointObjectName ], charsmax( aTempData[ PointObjectName ] ) );

		JSON_PointObject = json_object_get_value( JSON_Handle, aTempData[ PointObjectName ] );
		if ( JSON_PointObject != Invalid_JSON )
		{
			iJsonArraySize = json_array_get_count( JSON_PointObject );
			for ( j = 0; j < iJsonArraySize; j++ )
			{
				JSON_PointOrigin = json_array_get_value( JSON_PointObject, j );
				if ( JSON_PointOrigin != Invalid_JSON )
				{
					for ( k = 0; k < 3; k++ )
						aTempData[ PointOrigin ][ k ] = json_array_get_real( JSON_PointOrigin, k );

					ArrayPushArray( arHandle, aTempData );
					json_free( JSON_PointOrigin );
				}
			}

			json_free( JSON_PointObject );
		}
	}

	gl_iPointsCount = ArraySize( arHandle );
	json_free( JSON_Handle );

	server_print( "[%s] Loaded %i points on ^"%s^"", PluginPrefix, gl_iPointsCount, gl_szMapName );
}

public JSON_Points_Save( const Array: arHandle )
{
	if ( arHandle == Invalid_Array )
	{
		log_error( AMX_ERR_NATIVE, "[%s] Main Array is Invalid.", PluginPrefix );
		return;
	}

	new JSON: JSON_Handle = json_init_object( );
	new JSON: JSON_PointObject = Invalid_JSON;
	new JSON: JSON_PointOrigin = Invalid_JSON;
	new aTempData[ ePointsData ];

	for ( new i, j; i < gl_iPointsCount; i++ )
	{
		ArrayGetArray( arHandle, i, aTempData );

		if ( !json_object_has_value( JSON_Handle, aTempData[ PointObjectName ], JSONArray ) )
			JSON_PointObject = json_init_array( );
		else
			JSON_PointObject = json_object_get_value( JSON_Handle, aTempData[ PointObjectName ] );

		if ( JSON_PointObject != Invalid_JSON )
		{
			JSON_PointOrigin = json_init_array( );
			if ( JSON_PointOrigin != Invalid_JSON )
			{
				for ( j = 0; j < 3; j++ )
					json_array_append_real( JSON_PointOrigin, aTempData[ PointOrigin ][ j ] );

				json_array_append_value( JSON_PointObject, JSON_PointOrigin );
				json_free( JSON_PointOrigin );
			}

			json_object_set_value( JSON_Handle, aTempData[ PointObjectName ], JSON_PointObject );
			json_free( JSON_PointObject );
		}
	}

	json_serial_to_file( JSON_Handle, gl_szFilePath, true );
	json_free( JSON_Handle );
}

/* ~ [ Natives ] ~ */
public bool: native_get_random_point( const iPluginId, const iParamsCount )
{
	if ( !gl_iPointsCount )
	{
		log_amx( "[%s] There are no available points.", PluginPrefix );
		return false;
	}

	if ( gl_arMapPoints == Invalid_Array )
	{
		log_error( AMX_ERR_NATIVE, "[%s] Main Array is Invalid.", PluginPrefix );
		return false;
	}

	enum { arg_origin = 1, arg_object, arg_check_point_free };

	new szObjectName[ MAX_NAME_LENGTH ];
	get_string( arg_object, szObjectName, charsmax( szObjectName ) );

	new bool: bGetAll = bool: equali( szObjectName, "all" );
	if ( !IsNullString( szObjectName ) && !bGetAll && ArrayFindString( gl_arMapPoints, szObjectName ) == -1 )
		formatex( szObjectName, charsmax( szObjectName ), ObjectNames[ 0 ] );

	new aTempData[ ePointsData ];
	new Array: arTempPoints = ArrayCreate( 3, 0 );

	for ( new i; i < gl_iPointsCount; i++ )
	{
		ArrayGetArray( gl_arMapPoints, i, aTempData );
		if ( bGetAll || !bGetAll && equal( aTempData[ PointObjectName ], szObjectName ) )
			ArrayPushArray( arTempPoints, aTempData[ PointOrigin ] );
	}

	new iPointsCount = ArraySize( arTempPoints );
	if ( !iPointsCount )
	{
		log_error( AMX_ERR_NATIVE, "[%s] There are no available points in the ^"%s^" object.", PluginPrefix, szObjectName );
		return false;
	}

	SortADTArray( arTempPoints, Sort_Random, Sort_Float );

	if ( bool: get_param( arg_check_point_free ) )
	{
		new Vector3( vecOrigin );

		do {
			if ( !iPointsCount )
			{
				ArrayDestroy( arTempPoints );
				return false;
			}

			iPointsCount--;
			ArrayGetArray( arTempPoints, 0, aTempData[ PointOrigin ] );
			ArrayDeleteItem( arTempPoints, 0 );

			xs_vec_copy( aTempData[ PointOrigin ], vecOrigin );
		}
		while ( !IsPointFree( vecOrigin ) )
	}
	else
		ArrayGetArray( arTempPoints, 0, aTempData[ PointOrigin ] );

	ArrayDestroy( arTempPoints );

	set_array_f( arg_origin, aTempData[ PointOrigin ], 3 );
	return true;
}

public bool: native_get_random_points( const iPluginId, const iParamsCount )
{
	if ( !gl_iPointsCount )
	{
		log_amx( "[%s] There are no available points.", PluginPrefix );
		return false;
	}

	if ( gl_arMapPoints == Invalid_Array )
	{
		log_error( AMX_ERR_NATIVE, "[%s] Main Array is Invalid.", PluginPrefix );
		return false;
	}

	enum { arg_array = 1, arg_count, arg_object };

	new Array: arHandle = Array: get_param( arg_array );
	if ( arHandle == Invalid_Array )
	{
		log_error( AMX_ERR_NATIVE, "[%s] Array is Invalid!", PluginPrefix );
		return false;
	}

	new iGetPointsCount = get_param( arg_count );
	if ( !iGetPointsCount )
	{
		log_error( AMX_ERR_NATIVE, "[%s] The number of points cannot be 0 or negative.", PluginPrefix );
		return false;
	}

	new szObjectName[ MAX_NAME_LENGTH ];
	get_string( arg_object, szObjectName, charsmax( szObjectName ) );

	new bool: bGetAll = bool: equali( szObjectName, "all" );
	if ( !IsNullString( szObjectName ) && !bGetAll && ArrayFindString( gl_arMapPoints, szObjectName ) == -1 )
		formatex( szObjectName, charsmax( szObjectName ), ObjectNames[ 0 ] );

	new Array: arTempPoints = ArrayCreate( 3, 0 );
	for ( new i = 0, aTempData[ ePointsData ]; i < gl_iPointsCount; i++ )
	{
		ArrayGetArray( gl_arMapPoints, i, aTempData );
		if ( bGetAll || !bGetAll && equal( aTempData[ PointObjectName ], szObjectName ) )
			ArrayPushArray( arTempPoints, aTempData[ PointOrigin ] );
	}

	SortADTArray( arTempPoints, Sort_Random, Sort_Float );
	iGetPointsCount = min( iGetPointsCount, ArraySize( arTempPoints ) );

	new Vector3( vecOrigin );
	while ( iGetPointsCount-- ) {
		ArrayGetArray( arTempPoints, 0, vecOrigin );
		ArrayDeleteItem( arTempPoints, 0 );

		ArrayPushArray( arHandle, vecOrigin );
	}

	ArrayDestroy( arTempPoints );
	return true;
}

public bool: native_get_all_points( const iPluginId, const iParamsCount )
{
	if ( !gl_iPointsCount )
	{
		log_amx( "[%s] There are no available points.", PluginPrefix );
		return false;
	}

	if ( gl_arMapPoints == Invalid_Array )
	{
		log_error( AMX_ERR_NATIVE, "[%s] Main Array is Invalid.", PluginPrefix );
		return false;
	}

	enum { arg_array = 1, arg_object };

	new Array: arHandle = Array: get_param( arg_array );
	if ( arHandle == Invalid_Array )
	{
		log_error( AMX_ERR_NATIVE, "[%s] Array is Invalid!", PluginPrefix );
		return false;
	}

	new szObjectName[ MAX_NAME_LENGTH ];
	get_string( arg_object, szObjectName, charsmax( szObjectName ) );

	new bool: bGetAll = bool: equali( szObjectName, "all" );
	if ( !IsNullString( szObjectName ) && !bGetAll && ArrayFindString( gl_arMapPoints, szObjectName ) == -1 )
		formatex( szObjectName, charsmax( szObjectName ), ObjectNames[ 0 ] );

	for ( new i = 0, aTempData[ ePointsData ]; i < gl_iPointsCount; i++ )
	{
		ArrayGetArray( gl_arMapPoints, i, aTempData );
		if ( bGetAll || !bGetAll && equal( aTempData[ PointObjectName ], szObjectName ) )
			ArrayPushArray( arHandle, aTempData[ PointOrigin ] );
	}

	return true;
}

public native_free_array( const iPluginId, const iParamsCount )
{
	if ( gl_arMapPoints == Invalid_Array )
		return;

	gl_iPointsCount = 0;
	ArrayDestroy( gl_arMapPoints );
}

/* ~ [ Stocks ] ~ */
stock UTIL_GetEyePointAiming( const pPlayer, const Float: flDistance, Vector3( vecEndPos ), const iIgnoreId = DONT_IGNORE_MONSTERS )
{
	new Vector3( vecStart ); UTIL_GetEyePosition( pPlayer, vecStart );
	new Vector3( vecAiming ); UTIL_GetVectorAiming( pPlayer, vecAiming );
	new Vector3( vecEnd ); xs_vec_add_scaled( vecStart, vecAiming, flDistance, vecEnd );

	engfunc( EngFunc_TraceLine, vecStart, vecEnd, iIgnoreId, pPlayer, 0 );
	get_tr2( 0, TR_vecEndPos, vecEndPos );

	return get_tr2( 0, TR_pHit );
}

stock bool: IsPointFree( const Vector3( vecOrigin ) )
{
	engfunc( EngFunc_TraceHull, vecOrigin, vecOrigin, 0, HULL_HEAD, 0, 0 );
	if ( get_tr2( 0, TR_StartSolid ) || get_tr2( 0, TR_AllSolid ) || !get_tr2( 0, TR_InOpen ) )
		return false;

	/**
	 * After TraceHull, I do a search in the sphere, since TraceHull will not work
	 * on entities that have SOLID_TRIGGER/NOT, so if we find at least one entity in the sphere,
	 * then the point is not free.
	 */
	new Vector3( vecSrc ); xs_vec_copy( vecOrigin, vecSrc );
	vecSrc[ 2 ] -= 18.0;

	new pEntity = MaxClients; pEntity = engfunc( EngFunc_FindEntityInSphere, pEntity, vecSrc, 18.0 );
	if ( !is_nullent( pEntity ) )
	{
	#if defined EnableIgnoreList
		// Some default entities have SOLID_TRIGGER, so in order not to take them into account, we can skip them
		for ( new i = 0, iIterations = sizeof IgnoreEntitiesList; i < iIterations; i++ )
		{
			if ( FClassnameIs( pEntity, IgnoreEntitiesList[ i ] ) )
				return true;
		}
	#endif

		return false;
	}

	return true;
}

stock UTIL_PlaySound( const pPlayer, const szSoundPath[ ] )
{
	if ( szSoundPath[ strlen( szSoundPath ) - 1 ] == '3' )
		client_cmd( pPlayer, "mp3 play ^"sound/%s^"", szSoundPath );
	else
		client_cmd( pPlayer, "spk ^"%s^"", szSoundPath );
}

stock UTIL_TE_BEAMPOINTS_DEBUG( const iDest, const pReceiver, const Vector3( vecOrigin ), const iLife, const iColor[ ] )
{
	message_begin_f( iDest, SVC_TEMPENTITY, vecOrigin, pReceiver );
	write_byte( TE_BEAMPOINTS );
	write_coord_f( vecOrigin[ 0 ] );
	write_coord_f( vecOrigin[ 1 ] );
	write_coord_f( vecOrigin[ 2 ] - 36.0 );
	write_coord_f( vecOrigin[ 0 ] );
	write_coord_f( vecOrigin[ 1 ] );
	write_coord_f( vecOrigin[ 2 ] );
	write_short( gl_iszModelIndex_PointSprite ); // Model Index
	write_byte( 0 ); // Start Frame
	write_byte( 0 ); // FrameRate
	write_byte( iLife ); // Life in 0.1's
	write_byte( 8 ); // Line width in 0.1's
	write_byte( 0 ); // Noise
	write_byte( iColor[ 0 ] ); // Red
	write_byte( iColor[ 1 ] ); // Green
	write_byte( iColor[ 2 ] ); // Blue
	write_byte( 255 ); // Brightness
	write_byte( 0 ); // Scroll speed in 0.1's
	message_end( );
}

stock UTIL_TE_IMPLOSION( const iDest, const pReceiver, const Vector3( vecOrigin ), const iRadius = 128, const iCount = 20, const iLife = 5 )
{
	message_begin_f( iDest, SVC_TEMPENTITY, vecOrigin, pReceiver );
	write_byte( TE_IMPLOSION );
	write_coord_f( vecOrigin[ 0 ] );
	write_coord_f( vecOrigin[ 1 ] );
	write_coord_f( vecOrigin[ 2 ] );
	write_byte( iRadius ); // Radius
	write_byte( iCount ); // Count
	write_byte( iLife ); // Life time ( n * 0.1 sec )
	message_end( );
}

stock UTIL_TE_TELEPORT( const iDest, const pReceiver, const Vector3( vecOrigin ), const Float: flUp = 0.0 )
{
	message_begin_f( iDest, SVC_TEMPENTITY, vecOrigin, pReceiver );
	write_byte( TE_TELEPORT ); // TE id
	write_coord_f( vecOrigin[ 0 ] ); // X
	write_coord_f( vecOrigin[ 1 ] ); // Y
	write_coord_f( vecOrigin[ 2 ] + flUp ); // Z
	message_end( );
}

stock UTIL_GetEyePosition( const pPlayer, Vector3( vecEyeLevel ) )
{
	new Vector3( vecOrigin ); get_entvar( pPlayer, var_origin, vecOrigin );
	new Vector3( vecViewOfs ); get_entvar( pPlayer, var_view_ofs, vecViewOfs );

	xs_vec_add( vecOrigin, vecViewOfs, vecEyeLevel );
}

stock UTIL_GetVectorAiming( const pPlayer, Vector3( vecAiming ) ) 
{
	new Vector3( vecViewAngle ); get_entvar( pPlayer, var_v_angle, vecViewAngle );
	new Vector3( vecPunchAngle ); get_entvar( pPlayer, var_punchangle, vecPunchAngle );

	xs_vec_add( vecViewAngle, vecPunchAngle, vecViewAngle );
	angle_vector( vecViewAngle, ANGLEVECTOR_FORWARD, vecAiming );
}
