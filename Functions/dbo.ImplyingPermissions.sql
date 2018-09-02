SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
-- =============================================
-- Author:		MS script taken from http://technet.microsoft.com/en-us/library/ms177450(v=sql.105).aspx
-- Create date: 10/09/2013
-- Description:	The following sample script takes as its arguments the name of a class of a securable and the name of a permission. 
--				The sample traverses the permissions hierarchy, from a specified node to the root: CONTROL SERVER on the server. 
--				The sample emits the list of permissions that include the specified permission by implication.
--
-- Usage:		Call the function providing pairs of values from columns 1 & 2 from the list SQL Server Permissions available in
--				http://technet.microsoft.com/en-us/library/ms191291(v=sql.105).aspx
--
-- Examples:
--				SELECT * FROM dbo.ImplyingPermissions('schema', 'alter')
--				SELECT * FROM dbo.ImplyingPermissions('database', 'create schema')
--				SELECT * FROM dbo.ImplyingPermissions('object', 'view definition') 
--				SELECT * FROM dbo.ImplyingPermissions('route', 'take ownership')
-- =============================================
CREATE FUNCTION [dbo].[ImplyingPermissions] (
	@class nvarchar(64)
	, @permname nvarchar(64))
RETURNS @ImplPerms 
	TABLE (	permname nvarchar(64)
			, class nvarchar(64)
			, height int
			, rank int)
AS
BEGIN
	WITH class_hierarchy(class_desc, parent_class_desc) AS (
		SELECT DISTINCT class_desc, parent_class_desc 
			FROM sys.fn_builtin_permissions('')
	),
	PermT(class_desc, permission_name, covering_permission_name, parent_covering_permission_name, parent_class_desc)	AS (
		SELECT class_desc, permission_name, covering_permission_name,
				parent_covering_permission_name, parent_class_desc
			FROM sys.fn_builtin_permissions('')
	),
	permission_covers(permission_name, class_desc, level, inserted_as) AS (
		SELECT permission_name, class_desc, 0, 0
			FROM PermT
			WHERE permission_name = @permname 
				AND class_desc = @class
		UNION ALL
		SELECT covering_permission_name, class_desc, 0, 1
			FROM PermT 
			WHERE class_desc = @class AND 
			permission_name = @permname AND
			len(covering_permission_name) > 0
		UNION ALL
		SELECT PermT.covering_permission_name, 
				PermT.class_desc, permission_covers.level,
				permission_covers.inserted_as + 1
			FROM PermT, permission_covers 
			WHERE permission_covers.permission_name = PermT.permission_name 
				AND permission_covers.class_desc = PermT.class_desc 
				AND LEN(PermT.covering_permission_name) > 0
		UNION ALL
			SELECT PermT.parent_covering_permission_name,
					PermT.parent_class_desc,
					permission_covers.level + 1,
					permission_covers.inserted_as + 1
				FROM PermT, permission_covers, class_hierarchy
				WHERE permission_covers.permission_name = PermT.permission_name 
					AND permission_covers.class_desc = PermT.class_desc
					AND permission_covers.class_desc = class_hierarchy.class_desc
					AND class_hierarchy.parent_class_desc = PermT.parent_class_desc 
					AND LEN(PermT.parent_covering_permission_name) > 0
	)
	
	INSERT @ImplPerms
		SELECT DISTINCT permission_name, class_desc, 
				level, max(inserted_as) AS mia 
			FROM permission_covers
			GROUP BY class_desc, permission_name, level
			ORDER BY level, mia
	RETURN
END



GO
