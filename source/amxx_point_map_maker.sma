public stock const PluginName[ ] =			"[AMXX] Addon: Point Map Maker";
public stock const PluginVersion[ ] =		"1.0.7";
public stock const PluginAuthor[ ] =		"Yoshioka Haruki";

/* ~ [ Includes ] ~ */
#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <xs>
#include <reapi>
#include <json>
#include <point_map_maker>

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
	"sound/buttons/blip1.wav", // Positive Notification
	"sound/buttons/blip2.wav", // Negative Notification
	"sound/buttons/button2.wav" // Error
}
new const GetPointAngle[ ][ ] = {
	"NULL_VECTOR", "var_angles", "var_v_angle"
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
	new Array: gl_arIgnoreEntites;
#endif

new const DebugBeamColors[ ][ ] = {
	{ 255, 255, 255 }, // Not active object 
	{ 0, 255, 0 } // Active object
}

const Float: NearOriginDistance =			64.0; // Maximum distance when removing a point
const MenuPointMaker_Buttons =				( MENU_KEY_1|MENU_KEY_2|MENU_KEY_3|MENU_KEY_4|MENU_KEY_7|MENU_KEY_8|MENU_KEY_9|MENU_KEY_0 );
const TaskId_DebugPoints =					13250;

/* ~ [ Macroses ] ~ */
#if !defined Vector3
	#define Vector3(%0)						Float: %0[ 3 ]
#endif

#if !defined MAX_CONFIG_PATH_LENGHT
	#define MAX_CONFIG_PATH_LENGHT			128
#endif

#if !defined BIT
	#define BIT(%0)							( 1<<( %0 ) )
#endif

#define BIT_PLAYER(%0)						( BIT( %0 - 1 ) )
#define BIT_SUB(%0,%1)						( %0 &= ~%1 )
#define BIT_VALID(%0,%1)					( ( %0 & %1 ) == %1 )
#define BIT_INVERT(%0,%1)					( %0 ^= %1 )
#define BIT_CLEAR(%0)						( %0 = 0 )

#define IsNullString(%0)					bool: ( %0[ 0 ] == EOS )
#define IsNullVector(%0)					bool: ( ( %0[ 0 ] + %0[ 1 ] + %0[ 2 ] ) == 0.0 )
#define SetFormatex(%0,%1,%2)				( %1 = formatex( %0, charsmax( %0 ), %2 ) )
#define AddFormatex(%0,%1,%2)				( %1 += formatex( %0[ %1 ], charsmax( %0 ) - %1, %2 ) )

/* ~ [ Params ] ~ */
new gl_iPointsCount;
new gl_iObjectsCount;
new Array: gl_arObjectsNames;
new gl_pMenuIndex_PointMaker;
new gl_bitsUserShowAllPoints;
new gl_iszModelIndex_PointSprite;
new gl_szMapName[ MAX_NAME_LENGTH ];
new gl_szFilePath[ MAX_CONFIG_PATH_LENGHT ];

enum ePointsData {
	PointObjectName[ MAX_NAME_LENGTH ],
	Vector3( PointOrigin ),
	Vector3( PointAngles )
};
new Array: gl_arMapPoints;

enum eMenuData {
	MenuData_ObjectNow,
	MenuData_AngleType
};
new gl_aMenuData[ MAX_PLAYERS + 1 ][ eMenuData ];

enum {
	Sound_Positive,
	Sound_Negative,
	Sound_Error
};

enum {
	AngleType_NULL_VECTOR,
	AngleType_var_angles,
	AngleType_var_v_angle
};

/* ~ [ AMX Mod X ] ~ */
public plugin_natives( )
{
	register_native( "pmm_init_object", "native_init_object" );
	register_native( "pmm_points_count", "native_points_count" );
	register_native( "pmm_get_points", "native_get_points" );
	register_native( "pmm_get_point_data", "native_get_point_data" );
	register_native( "pmm_clear_points", "native_clear_points" );
}

public plugin_precache( )
{
	/* -> Precache Models <- */
	gl_iszModelIndex_PointSprite = engfunc( EngFunc_PrecacheModel, PointSprite );

	/* -> Create Array's <- */
	gl_arMapPoints = ArrayCreate( ePointsData, 0 );
	gl_arObjectsNames = ArrayCreate( MAX_NAME_LENGTH, 0 );

	/* -> Push default Object Name <- */
	ArrayPushString( gl_arObjectsNames, "general" );

	/* -> Call pre forward <- */
	new iForwardId;

	ExecuteForward( iForwardId = CreateMultiForward( "pmm_load_data_pre", ET_IGNORE ), _ );
	DestroyForward( iForwardId );

	/* -> Start Load Data <- */
	fnStartLoadData( );

	/* -> Call post forward <- */
	ExecuteForward( iForwardId = CreateMultiForward( "pmm_load_data_post", ET_IGNORE ), _ );
	DestroyForward( iForwardId );

	/* -> Cache objects count <- */
	gl_iObjectsCount = ArraySize( gl_arObjectsNames );
}

public plugin_init( )
{
	register_plugin( PluginName, PluginVersion, PluginAuthor );

	/* -> Lang Files <- */
	register_dictionary( "point_map_maker.txt" );

	/* -> Create Menus <- */
	register_menucmd( gl_pMenuIndex_PointMaker = register_menuid( "MenuPointMaker_Show" ), MenuPointMaker_Buttons, "MenuPointMaker_Handler" );

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
	arrayset( gl_aMenuData[ pPlayer ], 0, eMenuData );
}

/* ~ [ Other ] ~ */
public ConsoleCommand__PointMaker( const pCaller, const bitsFlags )
{
	if ( !is_user_connected( pCaller ) )
	{
		console_print( pCaller, "%l", "PMM_Console_OnlyForPlayer" );
		return PLUGIN_HANDLED;
	}

	if ( ( get_user_flags( pCaller ) & bitsFlags) != bitsFlags )
		return PLUGIN_HANDLED;

	MenuPointMaker_Show( pCaller );
	return PLUGIN_HANDLED;
}

public SendPlayerNotification( const pPlayer, const iSoundIndex, const szMessage[ ], any: ... )
{
	#define MAX_PRINT_LENGTH 191

	new szBuffer[ MAX_PRINT_LENGTH ];
	vformat( szBuffer, MAX_PRINT_LENGTH - 1, szMessage, 4 );

	SetGlobalTransTarget( pPlayer );

	UTIL_PlaySound( pPlayer, PluginSounds[ iSoundIndex ] );
	client_print_color( pPlayer, print_team_default, "^4[%s]^1 %s", PluginPrefix, szBuffer );
}

/* ~ [ Menus ] ~ */
public MenuPointMaker_Show( const pPlayer )
{
	if ( gl_arMapPoints == Invalid_Array )
		return;

	new szBuffer[ MAX_MENU_LENGTH ], iLen;

	SetGlobalTransTarget( pPlayer );

	SetFormatex( szBuffer, iLen, "%l^n^n", "PMM_Menu_Title", gl_szMapName, gl_iPointsCount );

	AddFormatex( szBuffer, iLen, "\y1. \w%l^n", "PMM_Menu_AddPoint" );
	AddFormatex( szBuffer, iLen, "\y2. \w%l^n", "PMM_Menu_RemovePoint" );

	new szObjectName[ MAX_NAME_LENGTH ];
	ArrayGetString( gl_arObjectsNames, gl_aMenuData[ pPlayer ][ MenuData_ObjectNow ], szObjectName, charsmax( szObjectName ) );

	AddFormatex( szBuffer, iLen, "\y3. \w%l^n", "PMM_Menu_SwitchObject", szObjectName );
	AddFormatex( szBuffer, iLen, "\y4. \w%l^n", "PMM_Menu_PointAngle", GetPointAngle[ gl_aMenuData[ pPlayer ][ MenuData_AngleType ] ] );
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
			ArrayGetString( gl_arObjectsNames, gl_aMenuData[ pPlayer ][ MenuData_ObjectNow ], aTempData[ PointObjectName ], charsmax( aTempData[ PointObjectName ] ) );

			get_entvar( pPlayer, var_origin, aTempData[ PointOrigin ] );

			if ( gl_aMenuData[ pPlayer ][ MenuData_AngleType ] == AngleType_NULL_VECTOR )
				xs_vec_copy( NULL_VECTOR, aTempData[ PointAngles ] );
			else
				get_entvar( pPlayer, ( gl_aMenuData[ pPlayer ][ MenuData_AngleType ] == AngleType_var_angles ) ? var_angles : var_v_angle, aTempData[ PointAngles ] );

			ArrayPushArray( gl_arMapPoints, aTempData );
			gl_iPointsCount++;

			new Vector3( vecOrigin ); xs_vec_copy( aTempData[ PointOrigin ], vecOrigin );
			UTIL_TE_IMPLOSION( MSG_ONE_UNRELIABLE, pPlayer, vecOrigin );

			SendPlayerNotification( pPlayer, Sound_Positive, "%l ^3#%i^1. %l: ^3^"%s^" ^1%l: ^3%.2f %.2f %.2f", "PMM_Chat_AddedPoint", gl_iPointsCount, "PMM_Chat_Object", aTempData[ PointObjectName ], "PMM_Chat_Origin", aTempData[ PointOrigin ][ 0 ], aTempData[ PointOrigin ][ 1 ], aTempData[ PointOrigin ][ 2 ] );
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
					if ( !gl_iPointsCount )
						BIT_CLEAR( gl_bitsUserShowAllPoints );

					new Vector3( vecOrigin ); xs_vec_copy( aTempData[ PointOrigin ], vecOrigin );
					UTIL_TE_TELEPORT( MSG_ONE_UNRELIABLE, pPlayer, vecOrigin );

					SendPlayerNotification( pPlayer, Sound_Negative, "%l ^3#%i^1. %l: ^3^"%s^" ^1%l: ^3%.2f %.2f %.2f", "PMM_Chat_DeletePoint", iFindOrigin + 1, "PMM_Chat_Object", aTempData[ PointObjectName ], "PMM_Chat_Origin", aTempData[ PointOrigin ][ 0 ], aTempData[ PointOrigin ][ 1 ], aTempData[ PointOrigin ][ 2 ] );
				}
				else
					SendPlayerNotification( pPlayer, Sound_Error, "%l", "PMM_Chat_NotFind", NearOriginDistance );
			}
			else
				SendPlayerNotification( pPlayer, Sound_Error, "%l","PMM_Chat_NoPoints" );
		}
		case 2: {
			if ( ++gl_aMenuData[ pPlayer ][ MenuData_ObjectNow ] >= gl_iObjectsCount )
				gl_aMenuData[ pPlayer ][ MenuData_ObjectNow ] = 0;
		}
		case 3: {
			if ( ++gl_aMenuData[ pPlayer ][ MenuData_AngleType ] >= sizeof GetPointAngle )
				gl_aMenuData[ pPlayer ][ MenuData_AngleType ] = 0;
		}
		case 6: {
			if ( gl_iPointsCount )
				BIT_INVERT( gl_bitsUserShowAllPoints, BIT_PLAYER( pPlayer ) );
			else
				SendPlayerNotification( pPlayer, Sound_Error, "%l %l", "PMM_Chat_NoPoints", "PMM_Chat_AddPointForUse" );

			set_task( 1.0, "CTask__DebugPoints", TaskId_DebugPoints + pPlayer, .flags = "b" );
		}
		case 7: {
			ArrayClear( gl_arMapPoints );

			BIT_CLEAR( gl_bitsUserShowAllPoints );
			gl_iPointsCount = 0;

			SendPlayerNotification( pPlayer, Sound_Negative, "%l", "PMM_Chat_DeteleAllPoints" );
		}
		case 8: {
			SendPlayerNotification( pPlayer, Sound_Positive, "%l", "PMM_Chat_SavePoints", gl_szFilePath );
			JSON_Points_Save( gl_arMapPoints );
		}
		case 9: {
			return;
		}
	}

	MenuPointMaker_Show( pPlayer );
}

/* ~ [ Tasks ] ~ */
public CTask__DebugPoints( const iTaskId )
{
	if ( !gl_bitsUserShowAllPoints || !gl_iPointsCount )
	{
		remove_task( iTaskId );
		return;
	}

	new pPlayer = iTaskId - TaskId_DebugPoints;
	if ( !BIT_VALID( gl_bitsUserShowAllPoints, BIT_PLAYER( pPlayer ) ) )
	{
		remove_task( iTaskId );
		return;
	}

	new aMenuData[ 2 ]; get_user_menu( pPlayer, aMenuData[ 0 ], aMenuData[ 1 ] );
	if ( aMenuData[ 0 ] != gl_pMenuIndex_PointMaker )
	{
		BIT_SUB( gl_bitsUserShowAllPoints, BIT_PLAYER( pPlayer ) );
		remove_task( iTaskId );

		return;
	}

	new szObjectName[ MAX_NAME_LENGTH ];
	ArrayGetString( gl_arObjectsNames, gl_aMenuData[ pPlayer ][ MenuData_ObjectNow ], szObjectName, charsmax( szObjectName ) );

	for ( new i = 0, aTempData[ ePointsData ], Vector3( vecStart ), Vector3( vecEnd ); i < gl_iPointsCount; i++ )
	{
		ArrayGetArray( gl_arMapPoints, i, aTempData );

		if ( !ExecuteHam( Ham_FVecVisible, pPlayer, aTempData[ PointOrigin ] ) )
			continue;

		xs_vec_copy( aTempData[ PointOrigin ], vecStart );
		xs_vec_copy( vecStart, vecEnd );
		vecEnd[ 2 ] -= 36.0;
		
		UTIL_TE_BEAMPOINTS_DEBUG( MSG_ONE_UNRELIABLE, pPlayer, vecStart, vecEnd, 10, DebugBeamColors[ strcmp( aTempData[ PointObjectName ], szObjectName ) == 0 ] );

		xs_vec_copy( aTempData[ PointAngles ], vecEnd );
		if ( IsNullVector( vecEnd ) )
			continue;

		angle_vector( vecEnd, ANGLEVECTOR_FORWARD, vecEnd );
		xs_vec_add_scaled( vecStart, vecEnd, 16.0, vecEnd );

		UTIL_TE_BEAMPOINTS_DEBUG( MSG_ONE_UNRELIABLE, pPlayer, vecStart, vecEnd, 10, { 255, 0, 0 } );
	}
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
	new aTempData[ ePointsData ];
	new JSON: JSON_ObjectHandle = Invalid_JSON;
	new JSON: JSON_PointHandle = Invalid_JSON;

	for ( new i, j; i < iJsonHandleSize; i++ )
	{
		json_object_get_name( JSON_Handle, i, aTempData[ PointObjectName ], charsmax( aTempData[ PointObjectName ] ) );

		// Can't find object name
		if ( ArrayFindString( gl_arObjectsNames, aTempData[ PointObjectName ] ) == -1 )
			continue;

		JSON_ObjectHandle = json_object_get_value( JSON_Handle, aTempData[ PointObjectName ] );
		if ( JSON_ObjectHandle != Invalid_JSON )
		{
			iJsonArraySize = json_array_get_count( JSON_ObjectHandle );
			for ( j = 0; j < iJsonArraySize; j++ )
			{
				JSON_PointHandle = json_array_get_value( JSON_ObjectHandle, j );
				if ( JSON_PointHandle != Invalid_JSON )
				{
					_json_get_point_array( JSON_PointHandle, "origin", aTempData[ PointOrigin ], 3 );
					_json_get_point_array( JSON_PointHandle, "angles", aTempData[ PointAngles ], 3 );

					ArrayPushArray( arHandle, aTempData );
					json_free( JSON_PointHandle );
				}
			}

			json_free( JSON_ObjectHandle );
		}
	}

	gl_iPointsCount = ArraySize( arHandle );
	json_free( JSON_Handle );
}

public JSON_Points_Save( const Array: arHandle )
{
	if ( arHandle == Invalid_Array )
	{
		log_error( AMX_ERR_NATIVE, "[%s] Main Array is Invalid.", PluginPrefix );
		return;
	}

	new JSON: JSON_Handle = Invalid_JSON;
	new JSON: JSON_ObjectHandle = Invalid_JSON;
	new JSON: JSON_PointHandle = Invalid_JSON;
	new aTempData[ ePointsData ];
	new Array: Array_LocalCache = ArrayCreate( 64, 1 );

	if ( file_exists( gl_szFilePath ) )
	{
		JSON_Handle = json_parse(gl_szFilePath, true);

		if ( JSON_Handle == Invalid_JSON)
		{
			log_error( AMX_ERR_NATIVE, "[%s] Failed to load existing JSON file.", PluginPrefix );
			return;
		}
	}
	else
	{
		JSON_Handle = json_init_object();
	}

	for ( new i; i < gl_iPointsCount; i++ )
	{
		ArrayGetArray( arHandle, i, aTempData );

		if ( json_object_has_value( JSON_Handle, aTempData[ PointObjectName ], JSONArray ) )
		{
			if ( ArrayFindString( Array_LocalCache, aTempData[ PointObjectName ] ) == -1 )
			{
				ArrayPushString( Array_LocalCache, aTempData[ PointObjectName ] );
				json_object_remove( JSON_Handle, aTempData[ PointObjectName ] );

				JSON_ObjectHandle = json_init_array( );
			}
			else
			{
				JSON_ObjectHandle = json_object_get_value( JSON_Handle, aTempData[ PointObjectName ] );
			}
		}
		else
		{
			JSON_ObjectHandle = json_init_array( );
		}

		if ( JSON_ObjectHandle != Invalid_JSON )
		{
			JSON_PointHandle = json_init_object( );
			if ( JSON_PointHandle != Invalid_JSON )
			{
				_json_add_point_array( JSON_PointHandle, "origin", aTempData[ PointOrigin ], 3 );
				_json_add_point_array( JSON_PointHandle, "angles", aTempData[ PointAngles ], 3 );

				json_array_append_value( JSON_ObjectHandle, JSON_PointHandle );
				json_free( JSON_PointHandle );
			}

			json_object_set_value( JSON_Handle, aTempData[ PointObjectName ], JSON_ObjectHandle );
			json_free( JSON_ObjectHandle );
		}
	}

	ArrayDestroy( Array_LocalCache );

	json_serial_to_file( JSON_Handle, gl_szFilePath, true );
	json_free( JSON_Handle );
}

_json_get_point_array( const JSON: JSON_ObjectHandle, const szValueName[ ], any: aBuffer[ ], const iBufferSize )
{
	if ( !json_object_has_value( JSON_ObjectHandle, szValueName, JSONArray ) )
		return;

	new JSON: JSON_HandleTemp = json_object_get_value( JSON_ObjectHandle, szValueName );
	if ( JSON_HandleTemp != Invalid_JSON )
	{
		for ( new i = 0; i < iBufferSize; i++ )
			aBuffer[ i ] = json_array_get_real( JSON_HandleTemp, i );

		json_free( JSON_HandleTemp );
	}
}

_json_add_point_array( const JSON: JSON_ObjectHandle, const szValueName[ ], const any: aBuffer[ ], const iBufferSize )
{
	new JSON: JSON_HandleTemp = json_init_array( );
	if ( JSON_HandleTemp != Invalid_JSON )
	{
		for ( new i = 0; i < iBufferSize; i++ )
			json_array_append_real( JSON_HandleTemp, aBuffer[ i ] );

		json_object_set_value( JSON_ObjectHandle, szValueName, JSON_HandleTemp );
		json_free( JSON_HandleTemp );
	}
}

fnStartLoadData( )
{
	/* -> Start Parse <- */
	get_mapname( gl_szMapName, charsmax( gl_szMapName ) );

	get_localinfo( "amxx_configsdir", gl_szFilePath, charsmax( gl_szFilePath ) );
	strcat( gl_szFilePath, MainFolder, charsmax( gl_szFilePath ) );

	if ( !dir_exists( gl_szFilePath ) )
		mkdir( gl_szFilePath );

	strcat( gl_szFilePath, fmt( "/%s.json", gl_szMapName ), charsmax( gl_szFilePath ) );

	JSON_Points_Load( gl_arMapPoints );
	server_print( "[%s] Loaded %i points on ^"%s^"", PluginPrefix, gl_iPointsCount, gl_szMapName );

#if defined EnableIgnoreList
	/* -> Add Ignore list <- */
	new iArraySize = sizeof IgnoreEntitiesList;
	gl_arIgnoreEntites = ArrayCreate( MAX_NAME_LENGTH, iArraySize );

	for ( new i = 0; i < iArraySize; i++ )
		ArrayPushString( gl_arIgnoreEntites, IgnoreEntitiesList[ i ] );
#endif
}

/* ~ [ Natives ] ~ */
public bool: native_init_object( const iPluginId, const iParamsCount )
{
	enum { arg_object = 1 };

	new szObjectName[ MAX_NAME_LENGTH ];
	get_string( arg_object, szObjectName, charsmax( szObjectName ) );

	if ( IsNullString( szObjectName ) )
		return false;

	if ( ArrayFindString( gl_arObjectsNames, szObjectName ) == -1 )
		ArrayPushString( gl_arObjectsNames, szObjectName );

	return true;
}

public native_points_count( const iPluginId, const iParamsCount )
{
	enum { arg_object = 1 };

	new szObjectName[ MAX_NAME_LENGTH ];
	get_string( arg_object, szObjectName, charsmax( szObjectName ) );

	if ( szObjectName[ 0 ] == '*' )
		return gl_iPointsCount;

	if ( ArrayFindString( gl_arMapPoints, szObjectName ) == -1 )
		return 0;

	new aTempData[ ePointsData ], iCount;
	for ( new i; i < gl_iPointsCount; i++ )
	{
		ArrayGetArray( gl_arMapPoints, i, aTempData );
		
		if ( strcmp( aTempData[ PointObjectName ], szObjectName ) == 0 )
			iCount += 1;
	}

	return iCount;
}

public any: native_get_points( const iPluginId, const iParamsCount )
{
	if ( !gl_iPointsCount )
	{
		log_error( AMX_ERR_NATIVE, "[%s] There are no available points.", PluginPrefix );
		return -1;
	}

	if ( gl_arMapPoints == Invalid_Array )
	{
		log_error( AMX_ERR_NATIVE, "[%s] Main Array is Invalid.", PluginPrefix );
		return -1;
	}

	enum { arg_object = 1, arg_count, arg_check_point_free, arg_callback };

	new iGetPointsCount = get_param( arg_count );
	if ( iGetPointsCount == 0 )
	{
		log_error( AMX_ERR_NATIVE, "[%s] The number of points cannot be 0.", PluginPrefix );
		return -1;
	}

	new szObjectName[ MAX_NAME_LENGTH ];
	get_string( arg_object, szObjectName, charsmax( szObjectName ) );

	if ( IsNullString( szObjectName ) )
	{
		log_error( AMX_ERR_NATIVE, "[%s] The Object name should not be empty.", PluginPrefix );
		return -1;
	}

	if ( ArrayFindString( gl_arObjectsNames, szObjectName ) == -1 )
	{
		log_error( AMX_ERR_NATIVE, "[%s] Could not be found object with name^"%s^".", PluginPrefix, szObjectName );
		return -1;
	}

	new aTempData[ ePointsData ];
	new Array: arTempPoints = ArrayCreate( .reserved = 0 );
	new bool: bFindFromAny = bool: ( szObjectName[ 0 ] == '*' );

	for ( new i; i < gl_iPointsCount; i++ )
	{
		ArrayGetArray( gl_arMapPoints, i, aTempData );

		if ( bFindFromAny || strcmp( aTempData[ PointObjectName ], szObjectName ) == 0 )
			ArrayPushCell( arTempPoints, i );
	}

	new iPointsCount = ArraySize( arTempPoints );
	if ( !iPointsCount )
	{
		log_error( AMX_ERR_NATIVE, "[%s] There are no available points in the ^"%s^" object.", PluginPrefix, szObjectName );
		ArrayDestroy( arTempPoints );

		return -1;
	}

	if ( iGetPointsCount == PMM_ALL_POINTS )
		return Array: arTempPoints;

	SortADTArray( arTempPoints, Sort_Random, Sort_Integer );

	if ( iGetPointsCount == 1 )
	{
		new iReturnPointIndex;

		if ( bool: get_param( arg_check_point_free ) )
		{
			new szCallBack[ MAX_NAME_LENGTH ];
			get_string( arg_callback, szCallBack, charsmax( szCallBack ) );

			new fwCallBack, iReturnForward;
			if ( !IsNullString( szCallBack ) )
				fwCallBack = CreateOneForward( iPluginId, szCallBack, FP_ARRAY );

			new Vector3( vecOrigin );

			do {
				if ( !iPointsCount )
				{
					iReturnPointIndex = -1;
					break;
				}

				iPointsCount--;
				ArrayGetArray( gl_arMapPoints, iReturnPointIndex = ArrayGetCell( arTempPoints, 0 ), aTempData );
				ArrayDeleteItem( arTempPoints, 0 );

				xs_vec_copy( aTempData[ PointOrigin ], vecOrigin );

				if ( fwCallBack )
				{
					ExecuteForward( fwCallBack, iReturnForward, PrepareArray( _: vecOrigin, 3 ) );

					if ( iReturnForward > 0 )
						break;
				}
			}
			while ( fwCallBack && iReturnForward <= 0 || !fwCallBack && !IsPointFree( vecOrigin ) )

			if ( fwCallBack )
				DestroyForward( fwCallBack );
		}
		else
			iReturnPointIndex = ArrayGetCell( arTempPoints, 0 );

		ArrayDestroy( arTempPoints );
		return iReturnPointIndex;
	}

	ArrayResize( arTempPoints, min( iGetPointsCount, iPointsCount ) );
	return Array: arTempPoints;
}

public bool: native_get_point_data( const iPluginId, const iParamsCount )
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

	enum { arg_point_index = 1, arg_origin, arg_angles };

	new iPointIndex = get_param( arg_point_index );
	if ( !( 0 <= iPointIndex < gl_iPointsCount ) )
	{
		log_error( AMX_ERR_NATIVE, "[%s] The point index has gone out of bounds. (%i)", PluginPrefix, iPointIndex );
		return false;
	}

	new aTempData[ ePointsData ];
	ArrayGetArray( gl_arMapPoints, iPointIndex, aTempData );

	set_array_f( arg_origin, aTempData[ PointOrigin ], 3 );
	set_array_f( arg_angles, aTempData[ PointAngles ], 3 );

	return true;
}

public bool: native_clear_points( const iPluginId, const iParamsCount )
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

	enum { arg_object = 1 };

	new szObjectName[ MAX_NAME_LENGTH ];
	get_string( arg_object, szObjectName, charsmax( szObjectName ) );

	if ( IsNullString( szObjectName ) )
	{
		log_error( AMX_ERR_NATIVE, "[%s] The Object name should not be empty.", PluginPrefix );
		return false;
	}

	if ( ( szObjectName[ 0 ] == '*' ) )
	{
		ArrayClear( gl_arMapPoints );
		gl_iPointsCount = 0;
	}
	else
	{
		for ( new i = ( gl_iPointsCount - 1 ), aTempData[ ePointsData ]; i >= 0; i-- )
		{
			ArrayGetArray( gl_arMapPoints, i, aTempData );

			if ( strcmp( aTempData[ PointObjectName ], szObjectName ) == 0 )
				ArrayDeleteItem( gl_arMapPoints, i );
		}

		gl_iPointsCount = ArraySize( gl_arMapPoints );
	}

	return true;
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
	new Vector3( vecSrc ); vecSrc = vecOrigin;
	vecSrc[ 2 ] -= 18.0;

	new pEntity = MaxClients; pEntity = engfunc( EngFunc_FindEntityInSphere, pEntity, vecSrc, 18.0 );
	if ( !is_nullent( pEntity ) )
	{
	#if defined EnableIgnoreList
		// Some default entities have SOLID_TRIGGER, so in order not to take them into account, we can skip them
		new szClassName[ MAX_NAME_LENGTH ]; get_entvar( pEntity, var_classname, szClassName, charsmax( szClassName ) );
		if ( ArrayFindString( gl_arIgnoreEntites, szClassName ) != -1 )
			return true;
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

stock UTIL_TE_BEAMPOINTS_DEBUG( const iDest, const pReceiver, const Vector3( vecStart ), const Vector3( vecEnd ), const iLife, const iColor[ ] )
{
	message_begin_f( iDest, SVC_TEMPENTITY, vecStart, pReceiver );
	write_byte( TE_BEAMPOINTS );
	write_coord_f( vecStart[ 0 ] );
	write_coord_f( vecStart[ 1 ] );
	write_coord_f( vecStart[ 2 ] );
	write_coord_f( vecEnd[ 0 ] );
	write_coord_f( vecEnd[ 1 ] );
	write_coord_f( vecEnd[ 2 ] );
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
