AmpersandApp.controller('static_logWindowController', function ($scope, $rootScope) {
		
	$rootScope.switchShowLogWindow = false;
	
	$rootScope.toggleShowLogWindow = function(){
		$rootScope.switchShowLogWindow = !$rootScope.switchShowLogWindow;
	}
	
});
